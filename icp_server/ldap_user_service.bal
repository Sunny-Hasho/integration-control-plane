// Copyright (c) 2026, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/crypto;
import ballerina/http;
import ballerina/ldap;
import ballerina/log;
import ballerina/time;

import icp_server.types;
import icp_server.utils;

// ── Listener address ──────────────────────────────────────────────────────────

// Set to true when LDAP is the active user store for this ICP deployment.
// This is read by the main ICP server to advertise the correct user-management capabilities.
configurable boolean ldapUserStoreEnabled = false;

// Port for the LDAP authentication adapter.
// To use this adapter, set authBackendUrl = "https://<host>:<ldapAuthServicePort>" in the ICP config.
// The default user service (default_user_service.bal) runs on port 9447; use a different port here.
configurable int ldapAuthServicePort = 9450;
configurable string ldapAuthServiceHost = "0.0.0.0";

// ── LDAP server connection ────────────────────────────────────────────────────

configurable string ldapHostName = "localhost";
configurable int ldapPort = 389;

// Distinguished Name and password for the admin/service account used to search
// the directory. Leave ldapConnectionName empty for anonymous bind.
configurable string ldapConnectionName = "";
configurable string ldapConnectionPassword = "";

// ── User search ───────────────────────────────────────────────────────────────

// Base DN under which users are located.
configurable string ldapUserSearchBase = "ou=Users,dc=wso2,dc=org";

// LDAP attribute that holds the login username.
// Use "uid" for standard LDAP and "sAMAccountName" for Active Directory.
configurable string ldapUserNameAttribute = "uid";

// Filter used to locate a single user entry. Use '?' as the username placeholder.
configurable string ldapUserSearchFilter = "(&(objectClass=person)(uid=?))";

// Optional: DN pattern to construct user DNs directly, skipping the search.
// Use '{0}' as the placeholder for the (escaped) username.
// Example: "uid={0},ou=Users,dc=wso2,dc=org"
// When empty, a directory search is performed. If the search result does not carry a
// parseable DN, the adapter falls back to constructing one from ldapUserNameAttribute
// and ldapUserSearchBase — which covers most flat directory layouts automatically.
// Only set this explicitly if your users live in nested OUs or require a non-standard DN form.
configurable string ldapUserDNPattern = "";

// Attribute used as the user's display name (e.g. "cn", "displayName").
// Falls back to the username if the attribute is absent or the lookup fails.
configurable string ldapDisplayNameAttribute = "cn";

// ── Role / group lookup ───────────────────────────────────────────────────────

// Set to false to skip role lookup entirely. Users will never receive super-admin
// via LDAP roles when this is false.
configurable boolean ldapReadGroups = true;

// --- memberOf strategy (Active Directory) ---
// Name of the user attribute that lists the group DNs the user belongs to.
// Example: "memberOf"
// When non-empty this strategy is used and the group-search settings below are ignored.
configurable string ldapMemberOfAttribute = "";

// --- Group-search strategy (standard LDAP) ---
// Base DN under which groups are searched.
configurable string ldapGroupSearchBase = "ou=Groups,dc=wso2,dc=org";

// Attribute on group entries that holds the group name used for role mapping.
configurable string ldapGroupNameAttribute = "cn";

// LDAP filter for group entries.
configurable string ldapGroupSearchFilter = "(objectClass=groupOfNames)";

// Attribute on group entries that lists its members.
// Use "member" / "uniqueMember" for standard LDAP or "memberUid" for posixGroup schemas.
configurable string ldapMembershipAttribute = "member";

// ── Admin role mapping ────────────────────────────────────────────────────────

// Names of LDAP groups whose members are granted ICP super-admin on every login.
// The comparison is case-sensitive and uses the ldapGroupNameAttribute value.
// Example: ["icp-admins", "administrators"]
configurable string[] ldapAdminRoles = [];

// ── TLS ───────────────────────────────────────────────────────────────────────

// Enable LDAPS (SSL). When true the adapter connects over TLS.
configurable boolean ldapSslEnabled = false;

// Path to a JKS truststore for verifying the LDAP server's certificate.
// Leave empty to disable certificate verification (suitable for testing only).
configurable string ldapTrustStorePath = "";
configurable string ldapTrustStorePassword = "";

// ── Resolved secrets ──────────────────────────────────────────────────────────

final string resolvedLdapConnectionPassword = check resolveSecret(ldapConnectionPassword);
final string resolvedLdapTrustStorePassword = check resolveSecret(ldapTrustStorePassword);

// ── Listener ──────────────────────────────────────────────────────────────────

listener http:Listener ldapAuthServiceListener = new (ldapAuthServicePort,
    config = {
        host: ldapAuthServiceHost,
        secureSocket: {
            key: {
                path: keystorePath,
                password: resolvedKeystorePassword
            }
        }
    }
);

http:Service ldapUserService = 
@http:ServiceConfig {
    auth: [
        {
            jwtValidatorConfig: {
                issuer: userServiceJwtIssuer,
                audience: userServiceJwtAudience,
                clockSkew: userServiceJwtClockSkewSeconds,
                signatureConfig: {
                    secret: resolvedUserServiceJwtHMACSecret
                }
            }
        }
    ]
}
service object {

    resource function post authenticate(@http:Payload types:Credentials request) returns http:Ok|http:Unauthorized|http:InternalServerError|error {

        log:printDebug("LDAP authenticate request", username = request.username);

        if request.username.trim() == "" || request.password.trim() == "" {
            return utils:createUnauthorizedError("Invalid credentials");
        }

        // 1. Resolve the user's Distinguished Name
        string|error userDN = resolveUserDN(request.username);
        if userDN is error {
            log:printDebug("User DN resolution failed",
                    username = request.username, reason = userDN.message());
            return utils:createUnauthorizedError("Invalid credentials");
        }

        // 2. Authenticate by attempting to bind with the user's DN and password
        boolean|error authResult = bindAsUser(userDN, request.password);
        if authResult is error {
            log:printError("Unexpected LDAP error during bind", authResult,
                    username = request.username);
            return utils:createInternalServerError("Authentication service unavailable");
        }
        if !authResult {
            log:printDebug("LDAP bind rejected — invalid credentials",
                    username = request.username);
            return utils:createUnauthorizedError("Invalid credentials");
        }

        log:printInfo("LDAP authentication successful", username = request.username);

        // 3. Derive a stable, deterministic userId for this LDAP user
        string userId = ldapDerivedUserId(request.username);

        // 4. Resolve the display name from the directory
        string displayName = resolveDisplayName(request.username, userDN);

        // 5. Fetch LDAP roles and decide super-admin status
        boolean isSuperAdmin = false;
        if ldapReadGroups && ldapAdminRoles.length() > 0 {
            string[]|error roles = getRolesForUser(request.username, userDN);
            if roles is error {
                log:printWarn("Could not retrieve LDAP roles; super-admin will not be granted",
                        username = request.username, reason = roles.message());
            } else {
                isSuperAdmin = isLdapSuperAdmin(roles);
                log:printDebug("LDAP role evaluation",
                        username = request.username, roles = roles,
                        isSuperAdmin = isSuperAdmin);
                if isSuperAdmin {
                    log:printInfo("User granted ICP super-admin via LDAP role",
                            username = request.username);
                }
            }
        }

        return <http:Ok>{
            body: {
                authenticated: true,
                userId: userId,
                displayName: displayName,
                isSuperAdmin: isSuperAdmin,
                timestamp: time:utcToString(time:utcNow())
            }
        };
    }
};

// ── LDAP connection helpers ────────────────────────────────────────────────────

// Build the ConnectionConfig for the admin (service-account) bind.
isolated function buildAdminConnectionConfig() returns ldap:ConnectionConfig {
    ldap:ConnectionConfig config = {
        hostName: ldapHostName,
        port: ldapPort,
        domainName: ldapConnectionName,
        password: resolvedLdapConnectionPassword
    };
    if ldapSslEnabled {
        config.clientSecureSocket = buildSecureSocket();
    }
    return config;
}

// Build the TLS socket config for LDAP connections.
isolated function buildSecureSocket() returns ldap:ClientSecureSocket {
    if ldapTrustStorePath.trim() != "" {
        return {
            enable: true,
            cert: {path: ldapTrustStorePath, password: resolvedLdapTrustStorePassword}
        };
    }
    // No truststore configured — disable certificate validation (testing only).
    return {enable: false};
}

// ── DN resolution ─────────────────────────────────────────────────────────────

// Resolve the LDAP Distinguished Name for the given username.
// If ldapUserDNPattern is set, constructs the DN directly.
// Otherwise, performs a directory search using the admin account.
isolated function resolveUserDN(string username) returns string|error {
    if ldapUserDNPattern.trim() != "" {
        return re`\{0\}`.replaceAll(ldapUserDNPattern, escapeForDN(username));
    }
    return searchForUserDN(username);
}

// Search the directory for the user entry and return its DN.
isolated function searchForUserDN(string username) returns string|error {
    ldap:Client adminClient = check new (buildAdminConnectionConfig());
    string filter = re`\?`.replaceAll(ldapUserSearchFilter, escapeForFilter(username));
    log:printDebug("Searching for user", searchBase = ldapUserSearchBase, filter = filter);
    ldap:SearchResult|ldap:Error result = adminClient->search(ldapUserSearchBase, filter, ldap:SUB);


    if result is ldap:Error {
        log:printError("LDAP user search failed", result, username = username);
        return error("LDAP user search failed");
    }

    ldap:Entry[]? entries = result.entries;
    if entries is () || entries.length() == 0 {
        return error(string `User '${username}' not found in LDAP directory`);
    }

    // Some connectors expose the DN as a regular attribute; try that first.
    ldap:AttributeType? dn = entries[0]["dn"];
    if dn is string && dn.trim() != "" {
        return dn;
    }

    // Fall back to constructing the DN from the username attribute and search base.
    // This works for the common case where all users live directly under ldapUserSearchBase.
    string constructed = string `${ldapUserNameAttribute}=${escapeForDN(username)},${ldapUserSearchBase}`;
    log:printDebug("DN not found in search result; using constructed DN",
            username = username, constructedDN = constructed);
    return constructed;
}

// ── Authentication (bind) ─────────────────────────────────────────────────────

// Try to bind to the LDAP server using the user's DN and password.
// Returns true on success, false for invalid credentials (LDAP result 49),
// and an error for unexpected connection failures.
isolated function bindAsUser(string userDN, string password) returns boolean|error {
    ldap:ConnectionConfig userConfig = {
        hostName: ldapHostName,
        port: ldapPort,
        domainName: userDN,
        password: password
    };
    if ldapSslEnabled {
        userConfig.clientSecureSocket = buildSecureSocket();
    }

    log:printDebug("Binding as user", userDN = userDN);
    ldap:Client|ldap:Error userClient = new (userConfig);
    if userClient is ldap:Error {
        // LDAP result code 49 signals INVALID_CREDENTIALS — treat as wrong password.
        string msg = userClient.message().toLowerAscii();
        if msg.includes("invalid_credentials") || msg.includes("invalid credentials")
                || msg.includes("49") {
            return false;
        }
        return error("Unexpected LDAP bind error: " + userClient.message());
    }
    return true;
}

// ── Display name resolution ───────────────────────────────────────────────────

// Fetch the display name for an authenticated user from the directory.
// Falls back to the plain username if the attribute is missing or the lookup fails.
isolated function resolveDisplayName(string username, string userDN) returns string {
    if ldapDisplayNameAttribute.trim() == "" {
        return username;
    }
    ldap:Client|ldap:Error adminClient = new (buildAdminConnectionConfig());
    if adminClient is ldap:Error {
        log:printWarn("Could not open LDAP connection to fetch display name; using username",
                adminClient);
        return username;
    }
    log:printDebug("Fetching display name for user", userDN = userDN, attribute = ldapDisplayNameAttribute);
    ldap:Entry|ldap:Error entry = adminClient->getEntry(userDN);

    if entry is ldap:Error {
        log:printWarn("Could not fetch display name attribute; using username", entry,
                username = username);
        return username;
    }

    ldap:AttributeType? nameAttr = entry[ldapDisplayNameAttribute];
    if nameAttr is string && nameAttr.trim() != "" {
        return nameAttr;
    }
    if nameAttr is string[] && nameAttr.length() > 0 {
        return nameAttr[0];
    }
    return username;
}

// ── Role / group lookup ───────────────────────────────────────────────────────

// Retrieve the LDAP group names for the given user.
// Delegates to the memberOf strategy (AD) or the group-search strategy (standard LDAP).
isolated function getRolesForUser(string username, string userDN) returns string[]|error {
    if ldapMemberOfAttribute.trim() != "" {
        return getRolesViaMemberOf(userDN);
    }
    return getRolesViaGroupSearch(username, userDN);
}

// Active Directory memberOf strategy:
// Read the group DNs from the user entry's memberOf attribute and extract
// the group name component (ldapGroupNameAttribute) from each DN.
isolated function getRolesViaMemberOf(string userDN) returns string[]|error {
    ldap:Client adminClient = check new (buildAdminConnectionConfig());
    log:printDebug("Fetching memberOf attribute for user", userDN = userDN, attribute = ldapMemberOfAttribute);
    ldap:Entry|ldap:Error entry = adminClient->getEntry(userDN);


    if entry is ldap:Error {
        return error("Failed to fetch memberOf attribute: " + entry.message());
    }

    ldap:AttributeType? memberOfAttr = entry[ldapMemberOfAttribute];
    string[] groupDNs = [];
    if memberOfAttr is string {
        groupDNs = [memberOfAttr];
    } else if memberOfAttr is string[] {
        groupDNs = memberOfAttr;
    }

    // Extract the group name from the RDN of each group DN
    return from string groupDN in groupDNs
        let string? name = extractAttrFromDN(groupDN, ldapGroupNameAttribute)
        where name is string
        select <string>name;
}

// Standard LDAP group-search strategy:
// Search for groups whose membership attribute contains the user's DN.
// For posixGroup (memberUid), the plain username is used instead of the full DN.
isolated function getRolesViaGroupSearch(string username, string userDN) returns string[]|error {
    string memberValue = ldapMembershipAttribute == "memberUid" ? username : userDN;
    string groupFilter = string `(&${ldapGroupSearchFilter}`
            + string `(${ldapMembershipAttribute}=${escapeForFilter(memberValue)}))`;

    ldap:Client adminClient = check new (buildAdminConnectionConfig());
    log:printDebug("Searching for user groups", searchBase = ldapGroupSearchBase, filter = groupFilter);
    ldap:SearchResult|ldap:Error result = adminClient->search(
            ldapGroupSearchBase, groupFilter, ldap:SUB);


    if result is ldap:Error {
        return error("LDAP group search failed: " + result.message());
    }

    ldap:Entry[]? entries = result.entries;
    if entries is () {
        return [];
    }

    string[] roles = [];
    foreach ldap:Entry groupEntry in entries {
        ldap:AttributeType? nameAttr = groupEntry[ldapGroupNameAttribute];
        if nameAttr is string && nameAttr.trim() != "" {
            roles.push(nameAttr);
        } else if nameAttr is string[] && nameAttr.length() > 0 {
            roles.push(nameAttr[0]);
        }
    }
    return roles;
}

// ── Utility functions ─────────────────────────────────────────────────────────

// Return true if any of the user's LDAP roles is in the configured admin roles list.
isolated function isLdapSuperAdmin(string[] userRoles) returns boolean {
    foreach string role in userRoles {
        foreach string adminRole in ldapAdminRoles {
            if role == adminRole {
                return true;
            }
        }
    }
    return false;
}

// Derive a deterministic UUID v5 for an LDAP user so that the same username under
// the same search base always maps to the same ICP user record across logins.
// Implements UUID v5 (SHA-1 + namespace) per RFC 4122.
isolated function ldapDerivedUserId(string username) returns string {
    // URL namespace bytes (RFC 4122 section 4.3)
    byte[] ns = [0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
                 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8];
    string name = string `ldap:${ldapUserSearchBase}:${username}`;
    byte[] input = [...ns, ...name.toBytes()];
    byte[] h = crypto:hashSha1(input);
    // Set version = 5 and variant = 10xx
    int v6 = (h[6] & 0x0f) | 0x50;
    int v8 = (h[8] & 0x3f) | 0x80;
    return string `${byteToHex(h[0])}${byteToHex(h[1])}${byteToHex(h[2])}${byteToHex(h[3])}`
        + string `-${byteToHex(h[4])}${byteToHex(h[5])}`
        + string `-${byteToHex(v6)}${byteToHex(h[7])}`
        + string `-${byteToHex(v8)}${byteToHex(h[9])}`
        + string `-${byteToHex(h[10])}${byteToHex(h[11])}${byteToHex(h[12])}${byteToHex(h[13])}${byteToHex(h[14])}${byteToHex(h[15])}`;
}

isolated function byteToHex(int b) returns string {
    string[] digits = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];
    return digits[(b >> 4) & 0xf] + digits[b & 0xf];
}

// Extract the value of a named attribute from an LDAP DN string.
// e.g. extractAttrFromDN("cn=admins,ou=groups,dc=example,dc=com", "cn") → "admins"
isolated function extractAttrFromDN(string dn, string attrName) returns string? {
    string prefix = attrName.toLowerAscii() + "=";
    string[] rdns = re`,`.split(dn);
    foreach string rdn in rdns {
        string trimmed = rdn.trim();
        if trimmed.toLowerAscii().startsWith(prefix) {
            return trimmed.substring(prefix.length());
        }
    }
    return ();
}

// Escape special characters for use in an LDAP search filter (RFC 4515).
// Escapes: \ * ( )
isolated function escapeForFilter(string value) returns string {
    string result = re`\\`.replaceAll(value, "\\5c");
    result = re`\*`.replaceAll(result, "\\2a");
    result = re`\(`.replaceAll(result, "\\28");
    result = re`\)`.replaceAll(result, "\\29");
    return result;
}

// Escape special characters for use in an LDAP DN value (RFC 4514).
// Escapes: \ , + " < > ;
isolated function escapeForDN(string value) returns string {
    string result = re`\\`.replaceAll(value, "\\\\");
    result = re`,`.replaceAll(result, "\\,");
    result = re`\+`.replaceAll(result, "\\+");
    result = re`"`.replaceAll(result, "\\\"");
    result = re`<`.replaceAll(result, "\\<");
    result = re`>`.replaceAll(result, "\\>");
    result = re`;`.replaceAll(result, "\\;");
    return result;
}

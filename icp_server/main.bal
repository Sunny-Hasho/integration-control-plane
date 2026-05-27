import ballerina/lang.runtime;
import ballerina/log;

public function main() returns error? {
    if ldapUserStoreEnabled {
        check ldapAuthServiceListener.attach(ldapUserService, "/");
        check ldapAuthServiceListener.'start();
        runtime:registerListener(ldapAuthServiceListener);
        log:printInfo("LDAP authentication adapter started",
                host = ldapAuthServiceHost, port = ldapAuthServicePort,
                ldapServer = ldapHostName + ":" + ldapPort.toString());
    } else {
        check defaultAuthServiceListener.attach(defaultUserService, "/");
        check defaultAuthServiceListener.'start();
        runtime:registerListener(defaultAuthServiceListener);
        log:printInfo("Authentication service started", host = authServiceHost, port = authServicePort);
    }
}

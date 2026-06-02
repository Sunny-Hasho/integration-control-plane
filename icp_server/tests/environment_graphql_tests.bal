import icp_server.auth;

import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import ballerina/test;

// =============================================================================
// Environment GraphQL Tests
// =============================================================================
// These tests verify RBAC v2 migration for environment management endpoints.
// Tokens:
//   - envAdminToken: User with full environment_mgt:manage permission
//   - envNonProdToken: User with environment_mgt:manage_nonprod permission only
// =============================================================================

// Test tokens for environment tests
string envAdminToken = "";
string envNonProdToken = "";

// JWT configuration
final readonly & jwt:IssuerSignatureConfig envTestJwtConfig = {
    algorithm: jwt:HS256,
    config: resolvedFrontendJwtHMACSecret
};

@test:BeforeSuite
function setupEnvironmentTests() returns error? {
    // Generate token for admin user with full environment management
    envAdminToken = check generateV2Token(
            "550e8400-e29b-41d4-a716-446655440000",
            "envadmin",
            [auth:PERMISSION_ENVIRONMENT_MANAGE, auth:PERMISSION_ENVIRONMENT_MANAGE_NONPROD, auth:PERMISSION_PROJECT_VIEW, auth:PERMISSION_INTEGRATION_VIEW]
    );

    // Generate token for non-prod only user
    envNonProdToken = check generateV2Token(
            "770e8400-e29b-41d4-a716-446655440001",
            "envnonprod",
            [auth:PERMISSION_ENVIRONMENT_MANAGE_NONPROD, auth:PERMISSION_PROJECT_VIEW, auth:PERMISSION_INTEGRATION_VIEW]
    );
}

@test:Config {
    groups: ["environment-graphql"]
}
function testGetEnvironmentsProjectLevel() returns error? {
    // Project-level user should see only environments in their project scope
    string query = string `
        query {
            environments {
                items {
                    id
                    name
                    critical
                    description
                }
                pageInfo { total limit offset }
            }
        }
    `;

    json payload = {query: query};
    http:Response response = check graphqlClient->post("/", payload, headers = {
        "Authorization": string `Bearer ${envAdminToken}`
    });

    json responsePayload = check response.getJsonPayload();
    io:println("testGetEnvironmentsProjectLevel Response: ", responsePayload);

    // Verify successful response
    test:assertTrue(responsePayload.data is json, "Response should contain data field");
    json data = check responsePayload.data;
    json environmentsPage = check data.environments;
    json[] environments = check environmentsPage.items.ensureType();

    io:println("Project admin sees environments count: ", environments.length());
}

@test:Config {
    groups: ["environment-graphql"],
    dependsOn: [testGetEnvironmentsProjectLevel]
}
function testGetEnvironmentsFilterByType() returns error? {
    // Test filtering by type: prod vs non-prod
    string queryProd = string `
        query {
            environments(type: "prod") {
                items {
                    id
                    name
                    critical
                }
                pageInfo { total limit offset }
            }
        }
    `;

    json payloadProd = {query: queryProd};
    http:Response responseProd = check graphqlClient->post("/", payloadProd, headers = {
        "Authorization": string `Bearer ${envAdminToken}`
    });

    json responseProdPayload = check responseProd.getJsonPayload();
    io:println("testGetEnvironmentsFilterByType (prod) Response: ", responseProdPayload);

    json prodData = check responseProdPayload.data;
    json prodEnvsPage = check prodData.environments;
    json[] prodEnvs = check prodEnvsPage.items.ensureType();

    // Verify all returned environments are critical (production)
    foreach json env in prodEnvs {
        json critical = check env.critical;
        test:assertTrue(critical == true, "All prod environments should have critical=true");
    }

    // Test non-prod filter
    string queryNonProd = string `
        query {
            environments(type: "non-prod") {
                items {
                    id
                    name
                    critical
                }
                pageInfo { total limit offset }
            }
        }
    `;

    json payloadNonProd = {query: queryNonProd};
    http:Response responseNonProd = check graphqlClient->post("/", payloadNonProd, headers = {
        "Authorization": string `Bearer ${envAdminToken}`
    });

    json responseNonProdPayload = check responseNonProd.getJsonPayload();
    io:println("testGetEnvironmentsFilterByType (non-prod) Response: ", responseNonProdPayload);

    json nonProdData = check responseNonProdPayload.data;
    json nonProdEnvsPage = check nonProdData.environments;
    json[] nonProdEnvs = check nonProdEnvsPage.items.ensureType();

    // Verify all returned environments are non-critical (non-production)
    foreach json env in nonProdEnvs {
        json critical = check env.critical;
        test:assertTrue(critical == false, "All non-prod environments should have critical=false");
    }
}


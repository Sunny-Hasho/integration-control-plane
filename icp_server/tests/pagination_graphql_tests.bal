// Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/test;

// =============================================================================
// Pagination GraphQL Tests
// =============================================================================
// These tests verify that pageInfo fields are correctly populated and that
// limit/offset pagination behaves correctly across resolvers.
// Token: orgDevToken (org-level Developer, integration:view at org scope)
// =============================================================================

// User ID that does not exist in the DB — gets zero effective permissions.
const string NO_PERM_USER_ID = "cc0e8400-e29b-41d4-a716-446655440099";

string paginationNoPermToken = "";

@test:BeforeSuite
function setupPaginationTests() returns error? {
    paginationNoPermToken = check generateV2Token(
            NO_PERM_USER_ID,
            "nopermuser",
            []
    );
}

// =============================================================================
// Test 1: No pagination parameter — resolver returns all items
//         pageInfo.limit should equal pageInfo.total (no slicing applied)
// =============================================================================

@test:Config {
    groups: ["pagination-graphql"]
}
function testPaginationNoPaginationParam() returns error? {
    string query = string `
        query {
            components(orgHandler: "default") {
                items { id name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Query should not return errors");

    json data = check response.data;
    json page = check data.components;
    json[] items = check page.items.ensureType();
    json pageInfo = check page.pageInfo;
    int total = check (check pageInfo.total).ensureType();
    int resultLimit = check (check pageInfo.'limit).ensureType();
    int offset = check (check pageInfo.offset).ensureType();

    test:assertEquals(items.length(), total, "All items should be returned when no pagination given");
    test:assertEquals(resultLimit, total, "limit should equal total when no pagination given");
    test:assertEquals(offset, 0, "offset should be 0 when no pagination given");
    test:assertTrue(total >= 2, "Seed data should have at least 2 components");
}

// =============================================================================
// Test 2: pagination limit:1 — returns exactly 1 item, pageInfo reflects limit
// =============================================================================

@test:Config {
    groups: ["pagination-graphql"],
    dependsOn: [testPaginationNoPaginationParam]
}
function testPaginationWithLimit() returns error? {
    string query = string `
        query {
            components(orgHandler: "default", options: { pagination: { limit: 1 } }) {
                items { id name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Query should not return errors");

    json data = check response.data;
    json page = check data.components;
    json[] items = check page.items.ensureType();
    json pageInfo = check page.pageInfo;
    int total = check (check pageInfo.total).ensureType();
    int resultLimit = check (check pageInfo.'limit).ensureType();
    int offset = check (check pageInfo.offset).ensureType();

    test:assertEquals(items.length(), 1, "Should return exactly 1 item");
    test:assertEquals(resultLimit, 1, "pageInfo.limit should be 1");
    test:assertEquals(offset, 0, "pageInfo.offset should be 0");
    test:assertTrue(total >= 2, "Total should reflect full count, not just this page");
}

// =============================================================================
// Test 3: pagination limit:1 offset:1 — returns next page
// =============================================================================

@test:Config {
    groups: ["pagination-graphql"],
    dependsOn: [testPaginationWithLimit]
}
function testPaginationWithOffset() returns error? {
    string query = string `
        query {
            components(orgHandler: "default", options: { pagination: { limit: 1, offset: 1 } }) {
                items { id name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Query should not return errors");

    json data = check response.data;
    json page = check data.components;
    json[] items = check page.items.ensureType();
    json pageInfo = check page.pageInfo;
    int offset = check (check pageInfo.offset).ensureType();

    test:assertEquals(items.length(), 1, "Should return 1 item from second page");
    test:assertEquals(offset, 1, "pageInfo.offset should be 1");
}

// =============================================================================
// Test 4: offset beyond total — items is empty, total still reflects full count
// =============================================================================

@test:Config {
    groups: ["pagination-graphql"],
    dependsOn: [testPaginationWithOffset]
}
function testPaginationOffsetBeyondTotal() returns error? {
    string query = string `
        query {
            components(orgHandler: "default", options: { pagination: { limit: 10, offset: 99999 } }) {
                items { id name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Query should not return errors");

    json data = check response.data;
    json page = check data.components;
    json[] items = check page.items.ensureType();
    json pageInfo = check page.pageInfo;
    int total = check (check pageInfo.total).ensureType();

    test:assertEquals(items.length(), 0, "Should return 0 items when offset exceeds total");
    test:assertTrue(total >= 2, "total should still reflect full count, not 0");
}

// =============================================================================
// Test 5: limit:9999 — clamped to MAX_PAGE_LIMIT (500) in pageInfo
// =============================================================================

@test:Config {
    groups: ["pagination-graphql"],
    dependsOn: [testPaginationOffsetBeyondTotal]
}
function testPaginationLimitClamp() returns error? {
    string query = string `
        query {
            components(orgHandler: "default", options: { pagination: { limit: 9999 } }) {
                items { id name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Query should not return errors");

    json data = check response.data;
    json page = check data.components;
    json pageInfo = check page.pageInfo;
    int resultLimit = check (check pageInfo.'limit).ensureType();

    test:assertEquals(resultLimit, 500, "limit:9999 should be clamped to MAX_PAGE_LIMIT=500");
}

// =============================================================================
// Test 6: componentSecrets with manage permission — returns list (may be empty)
// =============================================================================

@test:Config {
    groups: ["pagination-graphql", "component-secrets"]
}
function testComponentSecretsWithPermission() returns error? {
    string query = string `
        query GetComponentSecrets($componentId: String!, $environmentId: String!) {
            componentSecrets(componentId: $componentId, environmentId: $environmentId) {
                items { keyId }
                pageInfo { total limit offset }
            }
        }
    `;

    json variables = {
        componentId: COMPONENT_1_ID,
        environmentId: DEV_ENV_ID
    };

    // project1AdminToken has Admin role in Project 1 which includes integration:manage
    json response = check executeGraphQL(query, project1AdminToken, variables);

    test:assertFalse(response.errors is json, "Admin user should be able to query component secrets");

    json data = check response.data;
    json page = check data.componentSecrets;
    json[] items = check page.items.ensureType();
    json pageInfo = check page.pageInfo;
    int total = check (check pageInfo.total).ensureType();

    // items and total must be consistent (may be 0 if no secrets seeded)
    test:assertEquals(items.length(), total, "items count should match total when no pagination given");
}

// =============================================================================
// Test 7: componentSecrets with no permission — returns GraphQL error
// =============================================================================

@test:Config {
    groups: ["pagination-graphql", "component-secrets"]
}
function testComponentSecretsNoPermission() returns error? {
    string query = string `
        query GetComponentSecrets($componentId: String!, $environmentId: String!) {
            componentSecrets(componentId: $componentId, environmentId: $environmentId) {
                items { keyId }
                pageInfo { total limit offset }
            }
        }
    `;

    json variables = {
        componentId: COMPONENT_1_ID,
        environmentId: DEV_ENV_ID
    };

    json response = check executeGraphQL(query, paginationNoPermToken, variables);

    test:assertTrue(response.errors is json, "User without permissions should receive an error");

    json[] errors = check response.errors.ensureType();
    test:assertTrue(errors.length() > 0, "Should have at least one error");
}

// =============================================================================
// Test 8: componentSecrets with view-only permission — returns GraphQL error
//         Viewer has integration:view but not integration:manage
// =============================================================================

@test:Config {
    groups: ["pagination-graphql", "component-secrets"]
}
function testComponentSecretsViewOnlyPermission() returns error? {
    string query = string `
        query GetComponentSecrets($componentId: String!, $environmentId: String!) {
            componentSecrets(componentId: $componentId, environmentId: $environmentId) {
                items { keyId }
                pageInfo { total limit offset }
            }
        }
    `;

    json variables = {
        componentId: COMPONENT_1_ID,
        environmentId: DEV_ENV_ID
    };

    // orgDevToken has integration:view and integration:edit but NOT integration:manage
    json response = check executeGraphQL(query, orgDevToken, variables);

    test:assertTrue(response.errors is json, "View-only user should not access component secrets");
}

// =============================================================================
// Test 9: componentSecrets with pagination — pageInfo reflects the limit
// =============================================================================

@test:Config {
    groups: ["pagination-graphql", "component-secrets"],
    dependsOn: [testComponentSecretsWithPermission]
}
function testComponentSecretsPagination() returns error? {
    string query = string `
        query GetComponentSecrets($componentId: String!, $environmentId: String!) {
            componentSecrets(componentId: $componentId, environmentId: $environmentId,
                             pagination: { limit: 5, offset: 0 }) {
                items { keyId }
                pageInfo { total limit offset }
            }
        }
    `;

    json variables = {
        componentId: COMPONENT_1_ID,
        environmentId: DEV_ENV_ID
    };

    json response = check executeGraphQL(query, project1AdminToken, variables);

    test:assertFalse(response.errors is json, "Paginated query should not return errors");

    json data = check response.data;
    json page = check data.componentSecrets;
    json pageInfo = check page.pageInfo;
    int resultLimit = check (check pageInfo.'limit).ensureType();
    int offset = check (check pageInfo.offset).ensureType();

    test:assertEquals(resultLimit, 5, "pageInfo.limit should reflect requested limit");
    test:assertEquals(offset, 0, "pageInfo.offset should be 0");
}

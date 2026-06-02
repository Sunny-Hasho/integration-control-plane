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
// Services and Listeners GraphQL Tests
// =============================================================================
// These tests verify RBAC and response structure for the services(runtimeId)
// and listeners(runtimeId) resolvers.
//
// Behaviour table:
//   - Runtime not found  → GraphQL error
//   - No permission      → empty {items:[], pageInfo:{total:0,...}}
//   - Has permission     → list (may be empty if no artifacts seeded)
// =============================================================================

// A UUID that doesn't correspond to any seeded runtime.
const string SL_INVALID_RUNTIME_ID = "00000000-0000-0000-0000-000000000001";

string slNoPermToken = "";

@test:BeforeSuite
function setupServicesListenersTests() returns error? {
    slNoPermToken = check generateV2Token(
            NO_PERM_USER_ID,
            "nopermuser",
            []
    );
}

// =============================================================================
// SERVICES TESTS
// =============================================================================

// Test 1: services — org-level user can query services for an existing runtime
@test:Config {
    groups: ["services-listeners-graphql", "services-graphql"]
}
function testServicesForRuntime() returns error? {
    string query = string `
        query {
            services(runtimeId: "${RUNTIME_1_ID}") {
                items { name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Org-level user should be able to query services");

    json data = check response.data;
    json page = check data.services;
    json[] items = check page.items.ensureType();
    json pageInfo = check page.pageInfo;
    int total = check (check pageInfo.total).ensureType();

    test:assertEquals(items.length(), total, "items count should match total");
}

// Test 2: services — non-existent runtime returns a GraphQL error
@test:Config {
    groups: ["services-listeners-graphql", "services-graphql"]
}
function testServicesRuntimeNotFound() returns error? {
    string query = string `
        query {
            services(runtimeId: "${SL_INVALID_RUNTIME_ID}") {
                items { name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertTrue(response.errors is json, "Non-existent runtime should return an error");

    json[] errors = check response.errors.ensureType();
    test:assertTrue(errors.length() > 0, "Should have at least one error");
}

// Test 3: services — user with no DB permissions gets empty list (not an error)
@test:Config {
    groups: ["services-listeners-graphql", "services-graphql"]
}
function testServicesNoPermission() returns error? {
    string query = string `
        query {
            services(runtimeId: "${RUNTIME_1_ID}") {
                items { name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, slNoPermToken);

    test:assertFalse(response.errors is json, "No-permission user should receive empty list, not an error");

    json data = check response.data;
    json page = check data.services;
    json[] items = check page.items.ensureType();
    int total = check (check (check page.pageInfo).total).ensureType();

    test:assertEquals(items.length(), 0, "No-permission user should see no services");
    test:assertEquals(total, 0, "total should be 0 for no-permission user");
}

// Test 4: services — pagination params are reflected in pageInfo
@test:Config {
    groups: ["services-listeners-graphql", "services-graphql"],
    dependsOn: [testServicesForRuntime]
}
function testServicesWithPagination() returns error? {
    string query = string `
        query {
            services(runtimeId: "${RUNTIME_1_ID}", pagination: { limit: 5, offset: 0 }) {
                items { name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Paginated services query should not return errors");

    json data = check response.data;
    json page = check data.services;
    json pageInfo = check page.pageInfo;
    int resultLimit = check (check pageInfo.'limit).ensureType();
    int offset = check (check pageInfo.offset).ensureType();

    test:assertEquals(resultLimit, 5, "pageInfo.limit should reflect requested limit");
    test:assertEquals(offset, 0, "pageInfo.offset should be 0");
}

// =============================================================================
// LISTENERS TESTS
// =============================================================================

// Test 5: listeners — org-level user can query listeners for an existing runtime
@test:Config {
    groups: ["services-listeners-graphql", "listeners-graphql"]
}
function testListenersForRuntime() returns error? {
    string query = string `
        query {
            listeners(runtimeId: "${RUNTIME_1_ID}") {
                items { name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Org-level user should be able to query listeners");

    json data = check response.data;
    json page = check data.listeners;
    json[] items = check page.items.ensureType();
    int total = check (check (check page.pageInfo).total).ensureType();

    test:assertEquals(items.length(), total, "items count should match total");
}

// Test 6: listeners — non-existent runtime returns a GraphQL error
@test:Config {
    groups: ["services-listeners-graphql", "listeners-graphql"]
}
function testListenersRuntimeNotFound() returns error? {
    string query = string `
        query {
            listeners(runtimeId: "${SL_INVALID_RUNTIME_ID}") {
                items { name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertTrue(response.errors is json, "Non-existent runtime should return an error");

    json[] errors = check response.errors.ensureType();
    test:assertTrue(errors.length() > 0, "Should have at least one error");
}

// Test 7: listeners — user with no DB permissions gets empty list (not an error)
@test:Config {
    groups: ["services-listeners-graphql", "listeners-graphql"]
}
function testListenersNoPermission() returns error? {
    string query = string `
        query {
            listeners(runtimeId: "${RUNTIME_1_ID}") {
                items { name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, slNoPermToken);

    test:assertFalse(response.errors is json, "No-permission user should receive empty list, not an error");

    json data = check response.data;
    json page = check data.listeners;
    json[] items = check page.items.ensureType();
    int total = check (check (check page.pageInfo).total).ensureType();

    test:assertEquals(items.length(), 0, "No-permission user should see no listeners");
    test:assertEquals(total, 0, "total should be 0 for no-permission user");
}

// Test 8: listeners — pagination params are reflected in pageInfo
@test:Config {
    groups: ["services-listeners-graphql", "listeners-graphql"],
    dependsOn: [testListenersForRuntime]
}
function testListenersWithPagination() returns error? {
    string query = string `
        query {
            listeners(runtimeId: "${RUNTIME_1_ID}", pagination: { limit: 5, offset: 0 }) {
                items { name }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Paginated listeners query should not return errors");

    json data = check response.data;
    json page = check data.listeners;
    json pageInfo = check page.pageInfo;
    int resultLimit = check (check pageInfo.'limit).ensureType();
    int offset = check (check pageInfo.offset).ensureType();

    test:assertEquals(resultLimit, 5, "pageInfo.limit should reflect requested limit");
    test:assertEquals(offset, 0, "pageInfo.offset should be 0");
}

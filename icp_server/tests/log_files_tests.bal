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
// Log Files GraphQL Tests
// =============================================================================
// These tests verify the logFilesByRuntime resolver for edge-case scenarios
// that don't require a live MI runtime (not-found, offline, no permission).
//
// Behaviour table:
//   - Runtime not found  → empty {count:0, files:[], pageInfo:{total:0,...}}
//   - No permission      → empty {count:0, files:[], pageInfo:{total:0,...}}
//   - Runtime offline    → GraphQL error "Runtime is not online"
// =============================================================================

const string LF_INVALID_RUNTIME_ID = "00000000-0000-0000-0000-000000000003";
// Runtime 3 is seeded as OFFLINE (Project 1, Component 2, Dev env)
const string LF_OFFLINE_RUNTIME_ID = "880e8400-e29b-41d4-a716-446655440003";

string lfNoPermToken = "";

@test:BeforeSuite
function setupLogFilesTests() returns error? {
    lfNoPermToken = check generateV2Token(
            NO_PERM_USER_ID,
            "nopermuser",
            []
    );
}

// =============================================================================
// Test 1: logFilesByRuntime — non-existent runtime returns empty response (no error)
// =============================================================================

@test:Config {
    groups: ["log-files-graphql"]
}
function testLogFilesByRuntimeNotFound() returns error? {
    string query = string `
        query {
            logFilesByRuntime(runtimeId: "${LF_INVALID_RUNTIME_ID}") {
                count
                files { fileName size }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Non-existent runtime should return empty response, not an error");

    json data = check response.data;
    json result = check data.logFilesByRuntime;
    int count = check (check result.count).ensureType();
    json[] files = check result.files.ensureType();
    int total = check (check (check result.pageInfo).total).ensureType();

    test:assertEquals(count, 0, "count should be 0 for non-existent runtime");
    test:assertEquals(files.length(), 0, "files should be empty for non-existent runtime");
    test:assertEquals(total, 0, "pageInfo.total should be 0");
}

// =============================================================================
// Test 2: logFilesByRuntime — offline runtime returns GraphQL error
//         LF_OFFLINE_RUNTIME_ID (Runtime 3) is seeded with status OFFLINE so
//         it reliably exercises the "not online" error path.
// =============================================================================

@test:Config {
    groups: ["log-files-graphql"]
}
function testLogFilesByRuntimeOffline() returns error? {
    string query = string `
        query {
            logFilesByRuntime(runtimeId: "${LF_OFFLINE_RUNTIME_ID}") {
                count
                files { fileName size }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertTrue(response.errors is json, "Offline runtime should return a GraphQL error");

    json[] errors = check response.errors.ensureType();
    test:assertTrue(errors.length() > 0, "Should have at least one error");

    // Verify the error message is about the runtime not being online
    json firstError = errors[0];
    string message = check (check firstError.message).ensureType();
    test:assertTrue(message.includes("not online"), string `Error should mention runtime status, got: ${message}`);
}

// =============================================================================
// Test 3: logFilesByRuntime — no-permission user gets empty response (no error)
// =============================================================================

@test:Config {
    groups: ["log-files-graphql"]
}
function testLogFilesByRuntimeNoPermission() returns error? {
    string query = string `
        query {
            logFilesByRuntime(runtimeId: "${RUNTIME_1_ID}") {
                count
                files { fileName size }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, lfNoPermToken);

    test:assertFalse(response.errors is json, "No-permission user should get empty response, not an error");

    json data = check response.data;
    json result = check data.logFilesByRuntime;
    int count = check (check result.count).ensureType();
    json[] files = check result.files.ensureType();

    test:assertEquals(count, 0, "No-permission user should see count=0");
    test:assertEquals(files.length(), 0, "No-permission user should see no files");
}

// =============================================================================
// Test 4: logFilesByRuntime — offline runtime with searchKey still returns error
//         The online check happens after the permission check but before the
//         MI management API call, so search key does not bypass it.
// =============================================================================

@test:Config {
    groups: ["log-files-graphql"]
}
function testLogFilesByRuntimeOfflineWithSearchKey() returns error? {
    string query = string `
        query {
            logFilesByRuntime(runtimeId: "${LF_OFFLINE_RUNTIME_ID}", searchKey: "wso2") {
                count
                files { fileName size }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertTrue(response.errors is json, "Offline runtime should error even when searchKey is provided");

    json[] errors = check response.errors.ensureType();
    test:assertTrue(errors.length() > 0, "Should have at least one error");
}

// =============================================================================
// Test 5: logFilesByRuntime — pagination input accepted for offline runtime
//         Pagination params are valid syntax; the offline check still fires.
// =============================================================================

@test:Config {
    groups: ["log-files-graphql"]
}
function testLogFilesByRuntimeOfflineWithPagination() returns error? {
    string query = string `
        query {
            logFilesByRuntime(runtimeId: "${LF_OFFLINE_RUNTIME_ID}",
                              pagination: { limit: 5, offset: 0 }) {
                count
                files { fileName size }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertTrue(response.errors is json, "Offline runtime should error even with pagination params");
}

// =============================================================================
// Test 6: logFilesByRuntime — non-existent runtime with searchKey returns empty
// =============================================================================

@test:Config {
    groups: ["log-files-graphql"]
}
function testLogFilesByRuntimeNotFoundWithSearchKey() returns error? {
    string query = string `
        query {
            logFilesByRuntime(runtimeId: "${LF_INVALID_RUNTIME_ID}", searchKey: "wso2") {
                count
                files { fileName size }
                pageInfo { total limit offset }
            }
        }
    `;

    json response = check executeGraphQL(query, orgDevToken);

    test:assertFalse(response.errors is json, "Non-existent runtime should return empty response");

    json data = check response.data;
    json result = check data.logFilesByRuntime;
    int count = check (check result.count).ensureType();

    test:assertEquals(count, 0, "count should be 0 for non-existent runtime");
}

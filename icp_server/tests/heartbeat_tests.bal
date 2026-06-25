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

import icp_server.storage as storage;
import icp_server.types;

import ballerina/test;
import ballerina/time;

// Test data from seed: Component 2, Project 1, Dev env
// Component 2 / Dev env has Runtime 3 (OFFLINE, named). Using null-name replicas here
// won't conflict with that record since the OFFLINE cleanup query now filters by name.
const string HB_PROJECT_ID = "650e8400-e29b-41d4-a716-446655440001";
const string HB_COMPONENT_ID = "640e8400-e29b-41d4-a716-446655440002";
const string HB_ENV_ID = "750e8400-e29b-41d4-a716-446655440001";

// Fixed test UUIDs so cleanup is deterministic even if a test aborts mid-way.
const string HB_REPLICA1_ID = "aa000001-test-test-test-000000000001";
const string HB_REPLICA2_ID = "aa000001-test-test-test-000000000002";
const string HB_REPLICA3_ID = "aa000001-test-test-test-000000000003";
const string HB_RESTART_NEW_ID = "aa000001-test-test-test-000000000004";

// Offline Runtime 3 from seed data — used as the pre-existing OFFLINE record in the restart test.
const string HB_SEEDED_OFFLINE_ID = "880e8400-e29b-41d4-a716-446655440003";
const string HB_SEEDED_OFFLINE_NAME = "sample-integration-2-dev-runtime";

// =============================================================================
// Helpers
// =============================================================================

function buildHeartbeat(string runtimeId, string? runtimeName) returns types:Heartbeat {
    return {
        runtimeId: runtimeId,
        runtime: runtimeName,
        runtimeType: "BI",
        status: "RUNNING",
        environment: HB_ENV_ID,
        project: HB_PROJECT_ID,
        component: HB_COMPONENT_ID,
        version: "1.0.0",
        nodeInfo: {platformName: "ballerina"},
        artifacts: {},
        runtimeHash: "test-hash-" + runtimeId,
        timestamp: time:utcNow()
    };
}

function cleanupRuntime(string runtimeId) {
    error? result = storage:deleteRuntime(runtimeId);
    if result is error {
        // Ignore — runtime may have already been cleaned up or was never created.
    }
}

// =============================================================================
// Test 1: multi-replica null names — replicas must not delete each other
//
// Regression test for: https://github.com/wso2/product-integrator/issues/1780
//
// Before the fix, replica 2's heartbeat would find replica 1's RUNNING record
// (same component/env/null-name), treat it as a stale old instance, and delete it.
// After the fix (AND status = 'OFFLINE'), RUNNING records are never deleted this way.
// =============================================================================
@test:Config {
    groups: ["heartbeat", "multi-replica"]
}
function testMultiReplicaNullNamesBothSurvive() returns error? {
    // Ensure a clean slate before the test.
    cleanupRuntime(HB_REPLICA1_ID);
    cleanupRuntime(HB_REPLICA2_ID);

    // Replica 1 registers.
    types:HeartbeatResponse r1Response = check storage:processHeartbeat(
            buildHeartbeat(HB_REPLICA1_ID, ()), preResolved = true);
    test:assertTrue(r1Response.acknowledged, "Replica 1 heartbeat should be acknowledged");

    // Replica 2 registers. Before the fix this deleted Replica 1.
    types:HeartbeatResponse r2Response = check storage:processHeartbeat(
            buildHeartbeat(HB_REPLICA2_ID, ()), preResolved = true);
    test:assertTrue(r2Response.acknowledged, "Replica 2 heartbeat should be acknowledged");

    // Both replicas must still exist in the DB.
    types:Runtime? replica1 = check storage:getRuntimeById(HB_REPLICA1_ID);
    test:assertNotEquals(replica1, (), "Replica 1 must still exist after replica 2 registers");

    types:Runtime? replica2 = check storage:getRuntimeById(HB_REPLICA2_ID);
    test:assertNotEquals(replica2, (), "Replica 2 must exist");

    cleanupRuntime(HB_REPLICA1_ID);
    cleanupRuntime(HB_REPLICA2_ID);
}

// =============================================================================
// Test 2: five replicas null names — none of the 5 should delete each other
// =============================================================================
@test:Config {
    groups: ["heartbeat", "multi-replica"]
}
function testFiveReplicasNullNamesAllSurvive() returns error? {
    string[] replicaIds = [
        HB_REPLICA1_ID,
        HB_REPLICA2_ID,
        HB_REPLICA3_ID,
        "aa000001-test-test-test-000000000005",
        "aa000001-test-test-test-000000000006"
    ];

    foreach string id in replicaIds {
        cleanupRuntime(id);
    }

    foreach string id in replicaIds {
        types:HeartbeatResponse resp = check storage:processHeartbeat(
                buildHeartbeat(id, ()), preResolved = true);
        test:assertTrue(resp.acknowledged, string `Replica ${id} heartbeat should be acknowledged`);
    }

    // All 5 must coexist.
    foreach string id in replicaIds {
        types:Runtime? replica = check storage:getRuntimeById(id);
        test:assertNotEquals(replica, (), string `Replica ${id} must still exist after all replicas register`);
    }

    foreach string id in replicaIds {
        cleanupRuntime(id);
    }
}

// =============================================================================
// Test 3: VM restart — an OFFLINE record with the same name must be cleaned up
//
// Uses the seeded OFFLINE Runtime 3 (HB_SEEDED_OFFLINE_ID) as the "old instance".
// After this test that runtime no longer exists; this test therefore depends on no
// other test needing Runtime 3, and is placed in a separate "heartbeat-restart" group.
// If Runtime 3 is needed elsewhere, run this group in isolation.
// =============================================================================
@test:Config {
    groups: ["heartbeat", "heartbeat-restart"]
}
function testVmRestartCleansUpOfflineRecord() returns error? {
    cleanupRuntime(HB_RESTART_NEW_ID);

    // Pre-condition: seeded OFFLINE runtime must exist.
    types:Runtime? offlineRuntime = check storage:getRuntimeById(HB_SEEDED_OFFLINE_ID);
    if offlineRuntime is () {
        // If it was already cleaned up by a previous run, fail with a clear message.
        test:assertFail("Pre-condition failed: seeded OFFLINE runtime not found. " +
                "Re-seed the test database before running the heartbeat-restart group.");
    }

    // New instance comes up with the same name but a fresh UUID.
    types:HeartbeatResponse resp = check storage:processHeartbeat(
            buildHeartbeat(HB_RESTART_NEW_ID, HB_SEEDED_OFFLINE_NAME), preResolved = true);
    test:assertTrue(resp.acknowledged, "New instance heartbeat should be acknowledged");

    // Old OFFLINE record must have been cleaned up.
    types:Runtime? oldRecord = check storage:getRuntimeById(HB_SEEDED_OFFLINE_ID);
    test:assertEquals(oldRecord, (), "Old OFFLINE record must be deleted after restart");

    // New runtime must exist.
    types:Runtime? newRuntime = check storage:getRuntimeById(HB_RESTART_NEW_ID);
    test:assertNotEquals(newRuntime, (), "New runtime must be registered");

    cleanupRuntime(HB_RESTART_NEW_ID);
}

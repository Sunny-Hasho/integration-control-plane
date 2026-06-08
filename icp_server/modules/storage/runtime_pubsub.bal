// Copyright (c) 2025, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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

import ballerina/log;
import ballerina/websocket;

// Payload pushed to connected WebSocket clients on each status change.
public type RuntimeStatusEvent record {|
    string eventType = "RUNTIME_STATUS";
    string environmentId;
    string environmentName;
    string runtimeId;
    string status;
|};

// Payload pushed when a log level is changed for a runtime component.
public type LogLevelChangeEvent record {|
    string eventType = "LOG_LEVEL_CHANGE";
    string environmentId;
    string environmentName;
    string runtimeId;
    string loggerName;
    string logLevel;
|};

// Fan-out broadcaster over plain WebSocket connections.
// Each subscriber is identified by a unique clientId and is associated with
// a specific environmentId.  publish() writes a JSON message to every live
// caller for that environment; dead callers are pruned inline.
public isolated class RuntimeBroadcaster {
    private map<map<websocket:Caller>> topics = {};

    // Called by the WebSocket upgrade handler when a client connects.
    // Returns the clientId that must be passed to unsubscribe() on close.
    public isolated function subscribe(string environmentId, string clientId, websocket:Caller caller) {
        lock {
            map<websocket:Caller> callers = self.topics[environmentId] ?: {};
            callers[clientId] = caller;
            self.topics[environmentId] = callers;
            log:printInfo("WS client connected", environmentId = environmentId, clientId = clientId, total = callers.length());
        }
    }

    // Called when the WebSocket connection closes.
    public isolated function unsubscribe(string environmentId, string clientId) {
        lock {
            map<websocket:Caller>? callers = self.topics[environmentId];
            if callers is map<websocket:Caller> {
                _ = callers.remove(clientId);
                log:printInfo("WS client disconnected", environmentId = environmentId, clientId = clientId, remaining = callers.length());
            }
        }
    }

    // Called from heartbeat processing and the offline scheduler.
    // Writes to each live caller; removes callers that have already closed.
    // The lock is held only to snapshot callers and build the payload, then
    // released before I/O so that subscribe/unsubscribe are not blocked.
    public isolated function publish(string environmentId, string environmentName, string runtimeId, string status) {
        string payload;
        map<websocket:Caller> snapshot = {};
        lock {
            map<websocket:Caller>? callers = self.topics[environmentId];
            if callers is () || callers.length() == 0 {
                log:printDebug("No WS subscribers for runtime status event", environmentId = environmentId, runtimeId = runtimeId, status = status);
                return;
            }
            RuntimeStatusEvent event = {environmentId, environmentName, runtimeId, status};
            payload = event.toJson().toJsonString();
            foreach var [clientId, caller] in callers.entries() {
                snapshot[clientId] = caller;
            }
        }

        // Perform network I/O outside the lock.
        string[] dead = [];
        foreach var [clientId, caller] in snapshot.entries() {
            websocket:Error? err = caller->writeTextMessage(payload);
            if err is websocket:Error {
                dead.push(clientId);
            }
        }

        // Re-lock briefly to prune dead callers and log.
        // cloneReadOnly() produces an immutable copy that can cross the lock boundary.
        string[] & readonly deadSnapshot = dead.cloneReadOnly();
        lock {
            map<websocket:Caller>? callers = self.topics[environmentId];
            if callers is map<websocket:Caller> {
                foreach string clientId in deadSnapshot {
                    _ = callers.remove(clientId);
                }
                log:printInfo("Published runtime status event", environmentId = environmentId, environmentName = environmentName, runtimeId = runtimeId, status = status, subscribers = callers.length());
            }
        }
    }
    // Called when a log level is changed via the GraphQL mutation.
    // Uses the same lock-snapshot-I/O pattern as publish().
    public isolated function publishLogLevelChange(string environmentId, string environmentName, string runtimeId, string loggerName, string logLevel) {
        string payload;
        map<websocket:Caller> snapshot = {};
        lock {
            map<websocket:Caller>? callers = self.topics[environmentId];
            if callers is () || callers.length() == 0 {
                log:printDebug("No WS subscribers for log level change event", environmentId = environmentId, runtimeId = runtimeId, loggerName = loggerName);
                return;
            }
            LogLevelChangeEvent event = {environmentId, environmentName, runtimeId, loggerName, logLevel};
            payload = event.toJson().toJsonString();
            foreach var [clientId, caller] in callers.entries() {
                snapshot[clientId] = caller;
            }
        }

        string[] dead = [];
        foreach var [clientId, caller] in snapshot.entries() {
            websocket:Error? err = caller->writeTextMessage(payload);
            if err is websocket:Error {
                dead.push(clientId);
            }
        }

        string[] & readonly deadSnapshot = dead.cloneReadOnly();
        lock {
            map<websocket:Caller>? callers = self.topics[environmentId];
            if callers is map<websocket:Caller> {
                foreach string clientId in deadSnapshot {
                    _ = callers.remove(clientId);
                }
                log:printInfo("Published log level change event", environmentId = environmentId, environmentName = environmentName, runtimeId = runtimeId, loggerName = loggerName, logLevel = logLevel, subscribers = callers.length());
            }
        }
    }
}

// Module-level singleton shared by all call sites in the storage module.
public final RuntimeBroadcaster runtimeBroadcaster = new;

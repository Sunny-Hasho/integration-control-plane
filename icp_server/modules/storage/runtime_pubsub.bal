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
    string environmentId;
    string runtimeId;
    string status;
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
    public isolated function publish(string environmentId, string runtimeId, string status) {
        string payload;
        lock {
            map<websocket:Caller>? callers = self.topics[environmentId];
            if callers is () || callers.length() == 0 {
                log:printDebug("No WS subscribers for runtime status event", environmentId = environmentId, runtimeId = runtimeId, status = status);
                return;
            }
            payload = string `{"environmentId":"${environmentId}","runtimeId":"${runtimeId}","status":"${status}"}`;
            string[] dead = [];
            foreach var [clientId, caller] in callers.entries() {
                websocket:Error? err = caller->writeTextMessage(payload);
                if err is websocket:Error {
                    dead.push(clientId);
                }
            }
            foreach string clientId in dead {
                _ = callers.remove(clientId);
            }
            log:printInfo("Published runtime status event", environmentId = environmentId, runtimeId = runtimeId, status = status, subscribers = callers.length());
        }
    }
}

// Module-level singleton shared by all call sites in the storage module.
public final RuntimeBroadcaster runtimeBroadcaster = new;

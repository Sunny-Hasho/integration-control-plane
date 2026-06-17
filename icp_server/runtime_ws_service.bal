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

import icp_server.auth;
import icp_server.storage;
import icp_server.types;

import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/websocket;

// WebSocket listener shares the main HTTPS listener (port 9446) so the browser
// never needs to separately trust a second TLS certificate.
listener websocket:Listener wsListener = new (httpListener);

// WebSocket upgrade service at /runtime-status.
// Full URL: wss://host:9446/runtime-status?environmentId=<uuid>&token=<jwt>
//
// Auth: browsers cannot set custom headers on WebSocket upgrade requests, so
// the JWT is passed as ?token=.  environmentId is also a query param.
// Auth is checked before completing the upgrade.
@websocket:ServiceConfig {}
service /runtime\-status on wsListener {

    resource function get .(http:Request req) returns websocket:Service|websocket:UpgradeError {
        string? tokenParam = req.getQueryParamValue("token");
        string? environmentId = req.getQueryParamValue("environmentId");

        if tokenParam is () {
            return error websocket:UpgradeError("Authorization token missing");
        }
        if environmentId is () {
            return error websocket:UpgradeError("environmentId query parameter missing");
        }

        // Validate JWT and extract user context
        types:UserContextV2|error userCtx = auth:extractUserContextV2("Bearer " + tokenParam);
        if userCtx is error {
            log:printWarn("WS upgrade: invalid token", environmentId = environmentId);
            return error websocket:UpgradeError("Unauthorized: " + userCtx.message());
        }

        // Check environment-level permission
        types:AccessScope scope = auth:buildScopeFromContext("", envId = environmentId);
        boolean|error authorized = auth:hasAnyPermission(userCtx.userId,
                [auth:PERMISSION_ENVIRONMENT_MANAGE, auth:PERMISSION_ENVIRONMENT_MANAGE_NONPROD,
                 auth:PERMISSION_INTEGRATION_VIEW, auth:PERMISSION_INTEGRATION_EDIT,
                 auth:PERMISSION_INTEGRATION_MANAGE], scope);
        if authorized is error || !authorized {
            log:printWarn("WS upgrade: insufficient permissions", userId = userCtx.userId, environmentId = environmentId);
            return error websocket:UpgradeError("Unauthorized: insufficient permissions for environment " + environmentId);
        }

        log:printInfo("WS upgrade accepted", userId = userCtx.userId, environmentId = environmentId);
        return new RuntimeStatusWsService(environmentId);
    }
}

// Per-connection service.  Registered with the broadcaster on open, removed on close.
// Incoming client messages are ignored — this is a server-push-only channel.
service class RuntimeStatusWsService {
    *websocket:Service;
    private final string environmentId;
    private final string clientId;

    function init(string environmentId) {
        self.environmentId = environmentId;
        self.clientId = uuid:createType4AsString();
    }

    remote function onOpen(websocket:Caller caller) returns websocket:Error? {
        storage:runtimeBroadcaster.subscribe(self.environmentId, self.clientId, caller);
        log:printDebug("WS client opened", environmentId = self.environmentId, clientId = self.clientId);
    }

    remote function onMessage(websocket:Caller caller, string text) returns websocket:Error? {
        // Push-only channel — ignore any client messages.
    }

    remote function onClose(websocket:Caller caller, int statusCode, string reason) {
        storage:runtimeBroadcaster.unsubscribe(self.environmentId, self.clientId);
    }

    remote function onError(websocket:Caller caller, error err) {
        log:printWarn("WS error, removing client", err, environmentId = self.environmentId, clientId = self.clientId);
        storage:runtimeBroadcaster.unsubscribe(self.environmentId, self.clientId);
    }
}

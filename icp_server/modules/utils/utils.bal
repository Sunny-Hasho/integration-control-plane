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

import ballerina/graphql;
import ballerina/http;
import ballerina/log;
import icp_server.types;

// HTTP error response helpers

public isolated function createUnauthorizedError(string message) returns http:Unauthorized => {
    body: {
        message
    }
};

public isolated function createBadRequestError(string message) returns http:BadRequest => {
    body: {
        message
    }
};

public isolated function createForbiddenError(string message) returns http:Forbidden => {
    body: {
        message
    }
};

public isolated function createInternalServerError(string message) returns http:InternalServerError => {
    body: {
        message
    }
};

// GraphQL utilities

# Initialize GraphQL context with authorization header
#
# + reqCtx - HTTP request context
# + request - HTTP request
# + return - GraphQL context with authorization header set
public isolated function initGraphQLContext(http:RequestContext reqCtx, http:Request request) returns graphql:Context {
    string|error authorization = request.getHeader("Authorization");
    graphql:Context context = new;
    if authorization is string {
        context.set("Authorization", authorization);
    } else {
        // Fallback for WebSocket upgrade requests: browsers cannot set custom headers
        // during the WebSocket handshake, so the JWT is passed as a ?token= query param.
        string? tokenParam = request.getQueryParamValue("token");
        log:printDebug("initGraphQLContext WS upgrade", rawPath = request.rawPath, tokenFound = tokenParam is string);
        if tokenParam is string {
            context.set("Authorization", "Bearer " + tokenParam);
        }
    }
    string|http:HeaderNotFoundError xff = request.getHeader("X-Forwarded-For");
    if xff is string {
        context.set("clientIp", xff);
    } else {
        string|http:HeaderNotFoundError xri = request.getHeader("X-Real-IP");
        if xri is string {
            context.set("clientIp", xri);
        }
    }
    string|http:HeaderNotFoundError ua = request.getHeader("User-Agent");
    if ua is string {
        context.set("userAgent", ua);
    }
    return context;
}

// Runtime utilities

# Select a runtime from a list based on optional runtimeId
#
# + runtimes - List of runtimes to select from
# + componentId - Component ID for error messages
# + environmentId - Optional environment ID for error messages
# + runtimeId - Optional runtime ID to select; if not provided, returns first runtime
# + return - Selected runtime or error if not found
public isolated function selectRuntime(types:Runtime[] runtimes, string componentId, string? environmentId, string? runtimeId) returns types:Runtime|error {
    if runtimes.length() == 0 {
        return error("No runtimes found for this component");
    }
    types:Runtime runtime = runtimes[0];
    if runtimeId is string {
        foreach types:Runtime r in runtimes {
            if r.runtimeId == runtimeId {
                return r;
            }
        }
        return error(string `Runtime ${runtimeId} not found for component ${componentId}${environmentId is string ? string ` in environment ${environmentId}` : ""}`);
    }
    return runtime;
}

// Logger utilities

# Convert string to LogLevel enum with case-insensitive matching
#
# + level - Log level as string (e.g., "DEBUG", "info", "Warn")
# + return - LogLevel enum value or error if invalid
public isolated function toLogLevel(string level) returns types:LogLevel|error {
    string upperLevel = level.toUpperAscii();
    match upperLevel {
        "OFF" => {
            return types:OFF;
        }
        "TRACE" => {
            return types:TRACE;
        }
        "DEBUG" => {
            return types:DEBUG;
        }
        "INFO" => {
            return types:INFO;
        }
        "WARN" => {
            return types:WARN;
        }
        "ERROR" => {
            return types:ERROR;
        }
        "FATAL" => {
            return types:FATAL;
        }
        _ => {
            return error(string `Invalid log level: ${level}`);
        }
    }
}


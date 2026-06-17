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
import ballerina/lang.value;

// Intercepts every GraphQL field execution to inject WebSocket connectionParams auth.
//
// The graphql-ws protocol sends the JWT in the `connection_init` payload
// (connectionParams) rather than as an HTTP header, because browsers cannot set
// custom headers on WebSocket upgrade requests. Ballerina graphql 1.17.x exposes
// this payload in the GraphQL context under the "connectionParams" key.
//
// When found, the Authorization value is copied into the context "Authorization" key
// so that extractUserContext() — which reads from that key — can validate it without
// any changes to the resolver layer.
//
// For regular HTTP queries/mutations this interceptor is a no-op: the
// "Authorization" key is already set by initGraphQLContext from the HTTP header.
public readonly isolated service class WsAuthInterceptor {
    *graphql:Interceptor;

    isolated remote function execute(graphql:Context context, graphql:Field 'field) returns anydata|error {
        value:Cloneable|isolated object {}|error connectionParams = context.get("connectionParams");
        if connectionParams is map<anydata> {
            anydata authValue = connectionParams["Authorization"];
            if authValue is string && authValue.length() > 0 {
                context.set("Authorization", authValue);
            }
        }
        return context.resolve('field);
    }
}

--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local tracer = require("skywalking.tracer")
local client = require("skywalking.client")
local Span = require('skywalking.span')

local subsystem = ngx.config.subsystem

local SkyWalkingHandler = {
    PRIORITY = 100001,
    VERSION = "0.1.1",
}


function SkyWalkingHandler:init_worker()
    require("skywalking.util").set_randomseed()
end


function SkyWalkingHandler:access(config)
    if subsystem == "stream" then
        kong.log.warn("Not supportted to trace \"stream\" request yet.")
        return
    end
    local log = ngx.log
    log(ngx.ERR, "ngx.worker.count() is : ", ngx.worker.count())
    
    if config.sample_ratio == 100 or math.random() * 100 < config.sample_ratio then
        kong.ctx.plugin.skywalking_sample = true
        log(ngx.ERR, "my work id is : ", ngx.worker.id())
        if not client:isInitialized() then
            local metadata_buffer = ngx.shared.tracing_buffer
            metadata_buffer:set('serviceName', config.service_name)
            metadata_buffer:set('serviceInstanceName', config.service_instance_name)
            metadata_buffer:set('includeHostInEntrySpan', config.include_host_in_entry_span)
            log(ngx.ERR, "my work id is : ", ngx.worker.id(), "i will do startBackendTimer")
            client:startBackendTimer(config.backend_http_uri)
        end
        
        tracer:start(self:get_remote_peer(ngx.ctx.balancer_data))
    end
end


function SkyWalkingHandler:get_remote_peer(balancer_data)
    local peer = ''
    if balancer_data then
        if balancer_data.host then
            peer = balancer_data.host
        else
            peer = balancer_data.ip
        end
        peer = peer .. ':' .. balancer_data.port
    end
    return peer
end


function SkyWalkingHandler:body_filter(config)
    if ngx.arg[2] and kong.ctx.plugin.skywalking_sample then
        local entrySpan = ngx.ctx.entrySpan
        Span.tag(entrySpan, 'kong.node', kong.node.get_hostname())
        Span.setComponentId(entrySpan, 6001)

        local service = kong.router.get_service()
        if service and service.id then
            Span.tag(entrySpan, 'kong.service', service.id)
            local route = kong.router.get_route()
            if route and route.id then
                Span.tag(entrySpan, "kong.route", route.id)
            end
            if type(service.name) == "string" then
                Span.tag(entrySpan, "kong.service_name", service.name)
            end
        end
        Span.setComponentId(ngx.ctx.exitSpan, 6001)

        tracer:finish()
    end
end


function SkyWalkingHandler:log(config)
    tracer:prepareForReport()
end


return SkyWalkingHandler

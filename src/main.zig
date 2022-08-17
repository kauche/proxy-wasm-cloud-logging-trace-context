const std = @import("std");
const proxywasm = @import("proxy-wasm-zig-sdk");

extern fn __wasm_call_ctors() void;

const cloudTraceHeaderKey = "x-cloud-trace-context";
const cloudLoggingTraceHeaderKey = "x-cloud-logging-trace-context";

pub fn main() void {
    proxywasm.setNewRootContextFunc(newRootContext);
}

fn newRootContext(_: usize) *proxywasm.contexts.RootContext {
    var root = proxywasm.allocator.create(Root) catch unreachable;
    root.init();

    return &root.root_context;
}

const PluginConfiguration = struct {
    project_id: []const u8,
};

const Root = struct {
    const Self = @This();

    root_context: proxywasm.contexts.RootContext = undefined,
    plugin_configuration: PluginConfiguration = undefined,

    fn init(self: *Self) void {
        self.root_context = proxywasm.contexts.RootContext{
            .newHttpContextImpl = newHttpContext,
            .onPluginStartImpl = onPluginStart,
            .onDeleteImpl = onDelete,
        };
    }

    fn newHttpContext(root_context: *proxywasm.contexts.RootContext, _: u32) ?*proxywasm.contexts.HttpContext {
        const self: *Self = @fieldParentPtr(Self, "root_context", root_context);

        var context = proxywasm.allocator.create(CloudLoggingTraceHeaderConverter) catch unreachable;
        context.init(&self.plugin_configuration);

        return &context.http_context;
    }

    fn onPluginStart(root_context: *proxywasm.contexts.RootContext, configuration_size: usize) bool {
        const self: *Self = @fieldParentPtr(Self, "root_context", root_context);

        var plugin_config_data = proxywasm.hostcalls.getBufferBytes(proxywasm.enums.BufferType.PluginConfiguration, 0, configuration_size) catch |err| {
            log(proxywasm.enums.LogLevel.Error, "failed to get the configuration: {s}", .{@errorName(err)});
            return false;
        };
        defer plugin_config_data.deinit();

        var stream = std.json.TokenStream.init(plugin_config_data.raw_data);
        self.plugin_configuration = std.json.parse(
            PluginConfiguration,
            &stream,
            .{ .allocator = proxywasm.allocator },
        ) catch |err| {
            log(proxywasm.enums.LogLevel.Error, "failed to parse given configuration as JSON: {s}", .{@errorName(err)});
            return false;
        };

        return true;
    }

    fn onDelete(root_context: *proxywasm.contexts.RootContext) void {
        const self: *Self = @fieldParentPtr(Self, "root_context", root_context);
        proxywasm.allocator.destroy(self);
    }
};

const CloudLoggingTraceHeaderConverter = struct {
    const Self = @This();

    http_context: proxywasm.contexts.HttpContext = undefined,
    plugin_configuration: *PluginConfiguration,

    fn init(self: *Self, config: *PluginConfiguration) void {
        self.http_context = proxywasm.contexts.HttpContext{
            .onHttpRequestHeadersImpl = onHttpRequestHeaders,
            .onDeleteImpl = onDelete,
        };
        self.plugin_configuration = config;
    }

    fn onHttpRequestHeaders(http_context: *proxywasm.contexts.HttpContext, _: usize, _: bool) proxywasm.enums.Action {
        const self: *Self = @fieldParentPtr(Self, "http_context", http_context);

        var headers = proxywasm.hostcalls.getHeaderMap(proxywasm.enums.MapType.HttpRequestHeaders) catch |err| {
            log(proxywasm.enums.LogLevel.Error, "failed to get headers: {s}", .{@errorName(err)});
            return proxywasm.enums.Action.Continue;
        };
        defer headers.deinit();

        var traceHeader = headers.map.get(cloudTraceHeaderKey);
        if (traceHeader) |traceHeaderVal| {
            var it = std.mem.tokenize(u8, traceHeaderVal, "/");

            var traceID = it.next();
            if (traceID) |id| {
                const loggingHeader = std.fmt.allocPrint(proxywasm.allocator, "projects/{s}/traces/{s}", .{ self.plugin_configuration.project_id, id }) catch |err| {
                    log(proxywasm.enums.LogLevel.Error, "failed to format the logging header: {s}", .{@errorName(err)});
                    return proxywasm.enums.Action.Continue;
                };
                defer proxywasm.allocator.free(loggingHeader);

                proxywasm.hostcalls.replaceHeaderMapValue(proxywasm.enums.MapType.HttpRequestHeaders, cloudLoggingTraceHeaderKey, loggingHeader) catch |err| {
                    log(proxywasm.enums.LogLevel.Error, "failed to set the logging header: {s}", .{@errorName(err)});
                    return proxywasm.enums.Action.Continue;
                };
            }
        }

        return proxywasm.enums.Action.Continue;
    }

    fn onDelete(http_context: *proxywasm.contexts.HttpContext) void {
        const self: *Self = @fieldParentPtr(Self, "http_context", http_context);
        proxywasm.allocator.destroy(self);
    }
};

fn log(level: proxywasm.enums.LogLevel, comptime fmt: []const u8, args: anytype) void {
    const message = std.fmt.allocPrint(proxywasm.allocator, fmt, args) catch unreachable;
    defer proxywasm.allocator.free(message);
    proxywasm.hostcalls.log(level, message) catch unreachable;
}

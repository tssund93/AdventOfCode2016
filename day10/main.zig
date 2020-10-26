const std = @import("std");
const util = @import("util");
const AutoHashMap = std.hash_map.AutoHashMap;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const fmt = std.fmt;
const mem = std.mem;
const assert = std.debug.assert;
const print = std.debug.print;
const log = std.log;

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    const input = try util.readInput(allocator, 1024 * 1024);
    var lines = try util.split(allocator, fmt.trim(input), "\n");

    var state_part1 = State.init(allocator, 17, 61, 1);
    try populateInstructionsTable(allocator, &state_part1.instructions, lines);
    const part1 = try getResult(allocator, &state_part1, lines);
    print("Part 1: {}\n", .{part1});

    var state_part2 = State.init(allocator, 17, 61, 2);
    try populateInstructionsTable(allocator, &state_part2.instructions, lines);
    const part2 = try getResult(allocator, &state_part2, lines);
    print("Part 2: {}\n", .{part2});
}

fn populateInstructionsTable(
    allocator: *Allocator,
    instructions: *AutoHashMap(u16, *Instruction),
    lines: [][]const u8,
) !void {
    for (lines) |line| {
        const words = try util.split(allocator, fmt.trim(line), " ");
        defer allocator.free(words);
        if (mem.eql(u8, words[0], "bot")) {
            const bot_num = try fmt.parseUnsigned(u16, words[1], 10);
            const low_num = try fmt.parseUnsigned(u16, words[6], 10);
            const low_type: InstructionType = if (mem.eql(u8, words[5], "bot")) .bot else .output;
            const high_num = try fmt.parseUnsigned(u16, words[11], 10);
            const high_type: InstructionType = if (mem.eql(u8, words[10], "bot")) .bot else .output;
            var instruction = try allocator.create(Instruction);
            errdefer allocator.destroy(instruction);
            instruction.* = .{
                .low_to = .{ .num = low_num, .type = low_type },
                .high_to = .{ .num = high_num, .type = high_type },
            };
            try instructions.put(bot_num, instruction);
        }
    }
}

fn getResult(allocator: *Allocator, state: *State, lines: [][]const u8) !?u16 {
    for (lines) |line| {
        const words = try util.split(allocator, fmt.trim(line), " ");
        defer allocator.free(words);
        if (mem.eql(u8, words[0], "value")) {
            const chip_num = try fmt.parseUnsigned(u16, words[1], 10);
            const bot_num = try fmt.parseUnsigned(u16, words[5], 10);

            var bot = try registerBot(allocator, &state.bots, bot_num);
            const result = try bot.receive(state, chip_num);
            if (result != null) return result;
        }
    }
    return null;
}

const State = struct {
    const Self = @This();

    allocator: *Allocator,
    bots: AutoHashMap(u16, *Bot),
    instructions: AutoHashMap(u16, *Instruction),
    outputs: AutoHashMap(u16, u16),
    goal_low: u16,
    goal_high: u16,
    part: u2,

    fn init(allocator: *Allocator, goal_low: u16, goal_high: u16, part: u2) Self {
        return State{
            .bots = AutoHashMap(u16, *Bot).init(allocator),
            .instructions = AutoHashMap(u16, *Instruction).init(allocator),
            .outputs = AutoHashMap(u16, u16).init(allocator),
            .goal_low = goal_low,
            .goal_high = goal_high,
            .part = part,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Self) void {
        var bots_iter = self.bots.iterator();
        while (bots_iter.next()) |kv| {
            kv.value.deinit();
            self.allocator.destroy(kv.value);
        }
        self.bots.deinit();
        var instructions_iter = self.instructions.iterator();
        while (instructions_iter.next()) |kv| {
            self.allocator.destroy(kv.value);
        }
        self.instructions.deinit();
        self.outputs.deinit();
        self.* = undefined;
    }
};

const InstructionType = enum { bot, output };

const InstructionInfo = struct { type: InstructionType, num: u16 };

const Instruction = struct { low_to: InstructionInfo, high_to: InstructionInfo };

const Bot = struct {
    const Self = @This();

    allocator: *Allocator,
    number: u16,
    microchips: ArrayList(u16),

    fn init(allocator: *Allocator, bot_num: u16) !Self {
        const microchips = ArrayList(u16).init(allocator);
        errdefer microchips.deinit();
        return Self{
            .number = bot_num,
            .microchips = microchips,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Self) void {
        self.microchips.deinit();
        self.* = undefined;
    }

    fn receive(self: *Self, state: *State, chip_num: u16) !?u16 {
        assert(self.microchips.items.len < 2);
        try self.microchips.append(chip_num);

        if (self.microchips.items.len == 2) {
            return try self.carryOutInstruction(state);
        }
        return null;
    }

    fn carryOutInstruction(self: *Self, state: *State) CarryOutError!?u16 {
        assert(self.microchips.items.len == 2);
        std.sort.sort(u16, self.microchips.items, {}, comptime std.sort.desc(u16));

        assert(state.part == 1 or state.part == 2);
        if (state.part == 1 and
            self.microchips.items[0] == state.goal_high and
            self.microchips.items[1] == state.goal_low)
        {
            return self.number;
        }
        if (state.part == 2 and
            state.outputs.contains(0) and state.outputs.contains(1) and state.outputs.contains(2))
        {
            return state.outputs.get(0).? * state.outputs.get(1).? * state.outputs.get(2).?;
        }

        const instruction = state.instructions.get(self.number) orelse return error.InstructionNotFound;
        const low_microchip = self.microchips.pop();
        switch (instruction.low_to.type) {
            .bot => {
                var bot = try registerBot(self.allocator, &state.bots, instruction.low_to.num);
                const result = try bot.receive(state, low_microchip);
                if (result != null) return result;
            },
            .output => {
                _ = try state.outputs.put(instruction.low_to.num, low_microchip);
            },
        }
        const high_microchip = self.microchips.pop();
        switch (instruction.high_to.type) {
            .bot => {
                var bot = try registerBot(self.allocator, &state.bots, instruction.high_to.num);
                const result = try bot.receive(state, high_microchip);
                if (result != null) return result;
            },
            .output => {
                _ = try state.outputs.put(instruction.high_to.num, high_microchip);
            },
        }

        return null;
    }
};

const CarryOutError = error{InstructionNotFound} || mem.Allocator.Error;

fn registerBot(allocator: *Allocator, bots: *AutoHashMap(u16, *Bot), bot_num: u16) !*Bot {
    const res = try bots.getOrPut(bot_num);
    if (!res.found_existing) {
        var bot = try allocator.create(Bot);
        errdefer allocator.destroy(bot);
        bot.* = try Bot.init(allocator, bot_num);
        res.entry.value = bot;
    }
    return res.entry.value;
}

test "example test" {
    const allocator = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;
    var state = State.init(allocator, 2, 5, 1);
    defer state.deinit();

    const input =
        \\value 5 goes to bot 2
        \\bot 2 gives low to bot 1 and high to bot 0
        \\value 3 goes to bot 1
        \\bot 1 gives low to output 1 and high to bot 0
        \\bot 0 gives low to output 2 and high to output 0
        \\value 2 goes to bot 2
    ;
    var lines = try util.split(allocator, fmt.trim(input), "\n");
    defer allocator.free(lines);

    var part1: ?u16 = null;
    try populateInstructionsTable(allocator, &state.instructions, lines);
    while (part1 == null) {
        part1 = try getResult(allocator, &state, lines);
    }

    expectEqual(@as(?u16, 2), part1);
}
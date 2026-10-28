const std = @import("std");
const testing = std.testing;
const diag = @import("diag");

test "diagnostics print ok message" {
    // For M1 skeleton, just verify the function doesn't crash
    try diag.printOk("Test OK message");
    try testing.expect(true);
}

test "diagnostics print error message" {
    // Test that error printing works without crashing
    try diag.printError("Test error message");
    try testing.expect(true);
}

test "diagnostics severity enum" {
    // Test that the severity enum works as expected
    const ok_severity = diag.Severity.Ok;
    const error_severity = diag.Severity.Error;

    try testing.expect(ok_severity == diag.Severity.Ok);
    try testing.expect(error_severity == diag.Severity.Error);
    try testing.expect(ok_severity != error_severity);
}

// The semscope overlay of zmake (make lint). ADR-0026 records why semscope
// checks the Power of 10 rules. ADR-0003 adapts the rules to Zig.
package overlay

// R3 deviation (ADR-0003): zmake allocates from one arena for each
// invocation and frees nothing before exit. Hard limits cap the arena.
rules: "NASA-P10-03": enabled: false

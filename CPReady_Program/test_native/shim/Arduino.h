// Minimal Arduino shim so the firmware's header-only CompressionTracker can be
// compiled natively for an offline replay test. Not part of the project.
#pragma once
#include <cstdint>
#include <cmath>
#include <cstdio>
#include <string>

class String {
public:
    std::string s;
    String() {}
    String(const char* c) : s(c) {}
};

// Returns by value, like Arduino's min (a decltype(a < b ? a : b) return type would be
// a reference to a by-value parameter).
template <typename A, typename B>
inline auto min(A a, B b) { return a < b ? a : b; }

#ifndef PI
#define PI 3.1415926535897932384626433832795
#endif

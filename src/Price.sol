// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

type Price is uint256;

using {
    eq as ==,
    neq as !=,
    gt as >,
    gte as >=,
    lt as <,
    lte as <=,
    add as +,
    sub as -,
    mul,
    div
} for Price global;

function eq(Price a_, Price b_) pure returns (bool) {
    return a_ == b_;
}

function neq(Price a_, Price b_) pure returns (bool) {
    return a_ != b_;
}

function gt(Price a_, Price b_) pure returns (bool) {
    return a_ > b_;
}

function gte(Price a_, Price b_) pure returns (bool) {
    return a_ >= b_;
}

function lt(Price a_, Price b_) pure returns (bool) {
    return a_ < b_;
}

function lte(Price a_, Price b_) pure returns (bool) {
    return a_ <= b_;
}

function add(Price a_, Price b_) pure returns (Price) {
    return a_ + b_;
}

function sub(Price a_, Price b_) pure returns (Price) {
    return a_ - b_;
}

function mul(Price a_, uint256 b_) pure returns (Price) {
    return Price.wrap(Price.unwrap(a_) * b_);
}

function div(Price a_, uint256 b_) pure returns (Price) {
    return Price.wrap(Price.unwrap(a_) / b_);
}

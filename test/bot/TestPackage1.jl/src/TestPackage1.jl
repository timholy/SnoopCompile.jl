module TestPackage1
export hello, domath

hello(who::String) = "Hello, $who"
domath(x::Number) = x + 5

include("precompile_includer.jl")
end

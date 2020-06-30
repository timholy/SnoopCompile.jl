# for backward compatibiity test
SnoopCompile_path = dirname(dirname(dirname(dirname(dirname(@__DIR__)))))
if dirname(Base.current_project()) !== SnoopCompile_path
   using Pkg; Pkg.develop(PackageSpec(path=SnoopCompile_path))
end
using SnoopCompile # for backward compatibiity test

# using runtests:
snoop_bot(BotConfig("TestPackage4"), "$(@__DIR__)/example_script.jl")

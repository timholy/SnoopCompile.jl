using SnoopCompile

# using runtests:
@snoopi_bot BotConfig("TestPackage3", version = [v"1.0", v"1.4"], else_version = v"1.0")

# TODO: Add `@snoopc` into the mix
macro snoop_all(snoopl_csv_f, snoopl_yaml_f, snoopc_csv_f, commands)
    outsym = gensym(:output)
    esc(quote
        @snoopl pspawn=false $snoopl_csv_f $snoopl_yaml_f begin
            @snoopc pspawn=false $snoopc_csv_f begin
                global outsym = @snoopi_deep begin
                    @eval $commands
                end
            end
        end;
        outsym
    end)
end
-- digit_punct_fix.lua
-- 解决 RIME 在数字后输入点号/冒号弹出单候选框的问题，使其直接上屏

local P = {}

function P.init(env)
end

function P.func(key, env)
    local context = env.engine.context
    -- 仅处理按键按下，且当前没有正在进行的拼音输入或选单
    if not key:release() and not context:is_composing() and not context:has_menu() then
        local key_repr = key:repr()
        if key_repr == "period" or key_repr == "colon" then
            local latest = context.commit_history:latest_text()
            if latest and #latest > 0 and latest:match("[0-9]$") then
                if key_repr == "period" then
                    env.engine:commit_text(".")
                    return 1 -- 消费按键并直接上屏
                elseif key_repr == "colon" then
                    env.engine:commit_text(":")
                    return 1 -- 消费按键并直接上屏
                end
            end
        end
    end
    return 2 -- kNoop 放行
end

return P

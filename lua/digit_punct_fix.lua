-- digit_punct_fix.lua
-- 1. 解决 RIME 在数字后输入点号/冒号/逗号弹出单候选框的问题，使其直接上屏
-- 2. 拼音候选状态下输入符号（除 ,. 翻页外），符号直接追加进入候选 preedit；
--    随后按回车（Return/KP_Enter）：将拼音与符号原样上屏；
--    按空格或数字（1-9）：将对应候选词上屏并忽略/丢弃符号。

local P = {}

function P.init(env)
    env.symbol_attached = nil
    env.saved_candidate = nil
    env.saved_candidates = nil
    env.dquote_state = 0 -- 0: “，1: ”
    env.squote_state = 0 -- 0: ‘，1: ’
    env.last_quote_type = nil
end

local function is_symbol_key(key)
    if key:ctrl() or key:alt() or key:super() then
        return false
    end
    local code = key.keycode
    -- 排除逗号、句号（翻页），以及单双引号（交给专门的配对逻辑）
    if code == 0x2c or code == 0x2e or code == 0x22 or code == 0x27 then
        return false
    end
    -- ASCII 可见符号范围（排除字母、数字和空格）
    if (code >= 0x21 and code <= 0x2f) or   -- ! " # $ % & ' ( ) * + - /
       (code >= 0x3a and code <= 0x40) or   -- : ; < = > ? @
       (code >= 0x5b and code <= 0x60) or   -- [ \ ] ^ _ `
       (code >= 0x7b and code <= 0x7e) then  -- { | } ~
        return true
    end
    return false
end

function P.func(key, env)
    local context = env.engine.context

    if key:release() then
        return 2 -- kNoop
    end

    -- 英文模式下完全放行
    if context:get_option("ascii_mode") then
        return 2
    end

    -- =========================================================================
    -- 分支 A：处于拼音输入 / 候选列表状态
    -- =========================================================================
    if context:is_composing() or context:has_menu() then
        env.last_quote_type = nil
        local repr = key:repr()

        -- 1. 如果之前已经追加了符号：
        if env.symbol_attached then
            -- A1. 按回车：英文编码与符号原样上屏
            if repr == "Return" or repr == "KP_Enter" then
                env.engine:commit_text(context.input)
                context:clear()
                env.symbol_attached = nil
                env.saved_candidate = nil
                env.saved_candidates = nil
                return 1 -- kAccepted
            end

            -- A2. 按空格：上屏首选词，忽略符号
            if key.keycode == 0x20 then
                local cand = (env.saved_candidates and env.saved_candidates[1]) or env.saved_candidate
                if cand then
                    env.engine:commit_text(cand)
                else
                    env.engine:commit_text(context.input)
                end
                context:clear()
                env.symbol_attached = nil
                env.saved_candidate = nil
                env.saved_candidates = nil
                return 1 -- kAccepted
            end

            -- A3. 按数字 1~9：上屏对应序号的候选词，忽略符号
            local digit = nil
            if key.keycode >= 0x31 and key.keycode <= 0x39 then
                digit = key.keycode - 0x30
            elseif repr:match("^KP_([1-9])$") then
                digit = tonumber(repr:match("^KP_([1-9])$"))
            end
            if digit then
                local cand = (env.saved_candidates and env.saved_candidates[digit]) or env.saved_candidate
                if cand then
                    env.engine:commit_text(cand)
                    context:clear()
                    env.symbol_attached = nil
                    env.saved_candidate = nil
                    env.saved_candidates = nil
                    return 1 -- kAccepted
                end
            end

            -- A4. 按退格键：撤销追加的符号
            if repr == "BackSpace" then
                context:pop_input(1)
                env.symbol_attached = nil
                env.saved_candidate = nil
                env.saved_candidates = nil
                return 1 -- kAccepted
            end

            -- A5. 按 Escape：清除输入
            if repr == "Escape" then
                context:clear()
                env.symbol_attached = nil
                env.saved_candidate = nil
                env.saved_candidates = nil
                return 1 -- kAccepted
            end
        end

        -- 2. 检测是否按下了符号键（非 ,. 翻页）：
        if is_symbol_key(key) then
            -- 暂存当前候选词
            env.saved_candidate = nil
            env.saved_candidates = {}
            local sel = context:get_selected_candidate()
            if sel then
                env.saved_candidate = sel.text
            end
            pcall(function()
                local seg = context.composition:back()
                if seg then
                    for i = 0, 8 do
                        local c = seg:get_candidate_at(i)
                        if c then
                            table.insert(env.saved_candidates, c.text)
                        end
                    end
                end
            end)

            -- 将符号直接推入输入框（候选）
            local sym = string.char(key.keycode)
            env.symbol_attached = true
            context:push_input(sym)
            return 1 -- kAccepted
        end

        return 2 -- 其余按键（字母、,. 翻页等）放行给后续处理器
    end

    -- =========================================================================
    -- 分支 B：非输入状态（没在打拼音）
    -- =========================================================================
    local key_repr = key:repr()

    -- 中文模式下单双引号分别前后配对；英文模式已在前面直接放行
    if key_repr == "quotedbl" or (not key:ctrl() and not key:alt() and key.keycode == 0x22) then
        if env.dquote_state == 0 then
            env.engine:commit_text("“")
            env.dquote_state = 1
        else
            env.engine:commit_text("”")
            env.dquote_state = 0
        end
        env.last_quote_type = "double"
        return 1
    end

    if key_repr == "apostrophe" or (not key:ctrl() and not key:alt() and key.keycode == 0x27) then
        if env.squote_state == 0 then
            env.engine:commit_text("‘")
            env.squote_state = 1
        else
            env.engine:commit_text("’")
            env.squote_state = 0
        end
        env.last_quote_type = "single"
        return 1
    end

    -- 刚输入的引号被退格删除时，复位对应状态
    if key_repr == "BackSpace" then
        if env.last_quote_type == "double" then
            env.dquote_state = 0
        elseif env.last_quote_type == "single" then
            env.squote_state = 0
        end
        env.last_quote_type = nil
        return 2
    end

    -- 换行或 Esc 开启新的引号上下文
    if key_repr == "Return" or key_repr == "KP_Enter" or key_repr == "Escape" then
        env.dquote_state = 0
        env.squote_state = 0
        env.last_quote_type = nil
        return 2
    end

    if key_repr == "period" or key_repr == "colon" or key_repr == "comma" or key_repr == "KP_Decimal" then
        local latest = context.commit_history:latest_text()
        if latest and #latest > 0 and latest:match("[0-9]$") then
            if key_repr == "period" or key_repr == "KP_Decimal" then
                env.engine:commit_text(".")
                return 1 -- 消费并直接上屏
            elseif key_repr == "colon" then
                env.engine:commit_text(":")
                return 1 -- 消费并直接上屏
            elseif key_repr == "comma" then
                env.engine:commit_text(",")
                return 1 -- 消费并直接上屏
            end
        end
    end

    env.last_quote_type = nil
    env.symbol_attached = nil
    env.saved_candidate = nil
    env.saved_candidates = nil

    return 2 -- kNoop 放行
end

return P

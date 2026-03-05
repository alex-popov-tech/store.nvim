local M = {}

local GRADIENT_HALF_WIDTH = 2
local ASCII_ART_MAX_COL = 49
local DIAGONAL_SKEW = 3
local NUM_ROWS = 5
local TOTAL_STEPS = ASCII_ART_MAX_COL + 2 * GRADIENT_HALF_WIDTH + 1 + (NUM_ROWS - 1) * DIAGONAL_SKEW
local STEP_INTERVAL_MS = math.floor(3000 / TOTAL_STEPS)
local PAUSE_DURATION_MS = 10000
local GRADIENT_PROFILE = { 1, 2, 3, 2, 1 }
local INITIAL_DELAY_MS = 5000

local BLUE_GROUPS = { "StoreWaveBlue1", "StoreWaveBlue2", "StoreWaveBlue3" }
local YELLOW_GROUPS = { "StoreWaveYellow1", "StoreWaveYellow2", "StoreWaveYellow3" }

---Build a character map from buffer lines (true for non-space chars)
---@param buf_id number
---@param ns_id number
---@return boolean[][]
local function build_char_map(buf_id, ns_id)
  local char_map = {}
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, NUM_ROWS, false)
  for row = 0, NUM_ROWS - 1 do
    char_map[row] = {}
    local line = lines[row + 1] or ""
    for col = 0, ASCII_ART_MAX_COL - 1 do
      local byte = col + 1
      if byte <= #line then
        char_map[row][col] = line:sub(byte, byte) ~= " "
      else
        char_map[row][col] = false
      end
    end
  end
  return char_map
end

---Start a single sweep cycle
---@param state table
local function start_sweep(state)
  state.wave_center = -GRADIENT_HALF_WIDTH

  state.timer = vim.uv.new_timer()
  state.timer:start(
    0,
    STEP_INTERVAL_MS,
    vim.schedule_wrap(function()
      if not state.is_running or not vim.api.nvim_buf_is_valid(state.buf_id) then
        if state.timer and not state.timer:is_closing() then
          state.timer:stop()
          state.timer:close()
        end
        state.timer = nil
        return
      end

      vim.api.nvim_buf_clear_namespace(state.buf_id, state.ns_id, 0, -1)

      for row = 0, NUM_ROWS - 1 do
        local row_offset = row * DIAGONAL_SKEW
        for i = 1, #GRADIENT_PROFILE do
          local d = i - (GRADIENT_HALF_WIDTH + 1)
          local col = state.wave_center + d - row_offset
          if col >= 0 and col < ASCII_ART_MAX_COL then
            local level = GRADIENT_PROFILE[i]
            if state.char_map[row][col] then
              local groups = row < 3 and BLUE_GROUPS or YELLOW_GROUPS
              vim.api.nvim_buf_set_extmark(state.buf_id, state.ns_id, row, col, {
                end_col = col + 1,
                hl_group = groups[level],
              })
            end
          end
        end
      end

      state.wave_center = state.wave_center + 1

      if state.wave_center > ASCII_ART_MAX_COL + GRADIENT_HALF_WIDTH + (NUM_ROWS - 1) * DIAGONAL_SKEW then
        if state.timer and not state.timer:is_closing() then
          state.timer:stop()
          state.timer:close()
        end
        state.timer = nil

        if vim.api.nvim_buf_is_valid(state.buf_id) then
          vim.api.nvim_buf_clear_namespace(state.buf_id, state.ns_id, 0, -1)
        end

        if state.is_running then
          state.pause_timer = vim.fn.timer_start(PAUSE_DURATION_MS, function()
            if state.is_running then
              start_sweep(state)
            end
          end)
        end
      end
    end)
  )
end

---Start the wave animation on a buffer
---@param buf_id number
---@return table handle
function M.start(buf_id)
  local ns_id = vim.api.nvim_create_namespace("store_nvim_wave")

  local state = {
    buf_id = buf_id,
    ns_id = ns_id,
    timer = nil,
    pause_timer = nil,
    wave_center = 0,
    char_map = build_char_map(buf_id, ns_id),
    is_running = true,
  }

  state.initial_timer = vim.fn.timer_start(INITIAL_DELAY_MS, function()
    state.initial_timer = nil
    if state.is_running then
      start_sweep(state)
    end
  end)

  return state
end

---Stop the wave animation
---@param handle table
function M.stop(handle)
  handle.is_running = false

  if handle.initial_timer then
    vim.fn.timer_stop(handle.initial_timer)
    handle.initial_timer = nil
  end

  if handle.timer and not handle.timer:is_closing() then
    handle.timer:stop()
    handle.timer:close()
  end
  handle.timer = nil

  if handle.pause_timer then
    vim.fn.timer_stop(handle.pause_timer)
    handle.pause_timer = nil
  end

  if handle.buf_id and vim.api.nvim_buf_is_valid(handle.buf_id) then
    vim.api.nvim_buf_clear_namespace(handle.buf_id, handle.ns_id, 0, -1)
  end
end

---Refresh the character map after buffer content changes
---@param handle table
function M.refresh_char_map(handle)
  if handle.buf_id and vim.api.nvim_buf_is_valid(handle.buf_id) then
    handle.char_map = build_char_map(handle.buf_id, handle.ns_id)
  end
end

return M

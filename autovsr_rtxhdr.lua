local mp = require 'mp'

-- Configuration
local autovsr_enabled = true   -- Default: RTX Video Super Resolution enabled
local autohdr_enabled = true   -- Default: RTX Video HDR (SDR-to-HDR) enabled

-- Function to apply VSR and RTX HDR
local function apply_filters()
    -- Get video and display properties
    local video_width = mp.get_property_number("width")
    local video_height = mp.get_property_number("height")
    local display_width = mp.get_property_number("display-width")
    local display_height = mp.get_property_number("display-height")
    local codec = mp.get_property("video-codec", "")
    local pixelformat = mp.get_property("video-params/pixelformat", "")
    local primaries = mp.get_property("video-params/primaries", "")
    local gamma = mp.get_property("video-params/gamma", "")

    -- Validate properties
    if not (video_width and video_height and display_width and display_height and codec and pixelformat) then
        return
    end

    -- Calculate scale factor and round to nearest 0.1
    local scale = math.max(display_width / video_width, display_height / video_height)
    scale = math.floor(scale * 10) / 10

    -- Temporarily disable property change observation of "vf" to prevent recursive infinite loops
    mp.unobserve_property(apply_filters)

    -- Remove existing filters to avoid duplicates/conflicts
    mp.commandv("vf", "remove", "@format-nv12")
    mp.commandv("vf", "remove", "@rtx-vsr")
    mp.commandv("vf", "remove", "@rtx-hdr")
    mp.commandv("vf", "remove", "@rtx-combined")

    -- Detect if content is SDR (not native HDR)
    local is_sdr = true
    if primaries == "bt.2020" or gamma == "pq" or gamma == "hlg" then
        is_sdr = false
    end

    -- Apply format conversion for Main 10 HEVC if needed (VSR compatibility requirement)
    if codec:lower():match("hevc") or codec:lower():match("h%.265") then
        if pixelformat:match("p10le$") or pixelformat == "p010" then
            mp.commandv("vf", "append", "@format-nv12:format=nv12")
        end
    end

    local status_msg = ""

    -- Configure output colorspace for RTX HDR (Auto enables HDR swapchain on Windows 11)
    mp.set_property("d3d11-output-csp", "auto")

    -- Apply filters depending on user choice and capability
    if (scale > 1 and autovsr_enabled) and (is_sdr and autohdr_enabled) then
        -- Combined mode (VSR scaling + RTX HDR)
        -- We utilize x2bgr10 format to preserve depth and prevent artifacts during RTX HDR processing
        mp.commandv("vf", "append", "@rtx-combined:d3d11vpp=scaling-mode=nvidia:scale=" .. scale .. ":format=x2bgr10:nvidia-true-hdr")
        status_msg = "VSR (" .. scale .. "x) + RTX HDR"
    elseif scale > 1 and autovsr_enabled then
        -- VSR Only scaling
        mp.commandv("vf", "append", "@rtx-vsr:d3d11vpp=scaling-mode=nvidia:scale=" .. scale)
        status_msg = "VSR (" .. scale .. "x)"
    elseif is_sdr and autohdr_enabled then
        -- RTX HDR Only processing
        mp.commandv("vf", "append", "@rtx-hdr:d3d11vpp=format=x2bgr10:nvidia-true-hdr")
        status_msg = "RTX HDR"
    end

    -- Notify the user of the active status
    if status_msg ~= "" then
        mp.osd_message(status_msg .. " ACTIVE", 2)
    end

    -- Re-observe properties safely
    mp.observe_property("video-params", "native", apply_filters)
end

-- Toggle VSR dynamically
local function toggle_vsr()
    autovsr_enabled = not autovsr_enabled
    apply_filters()
    mp.osd_message("RTX VSR " .. (autovsr_enabled and "ON" or "OFF"), 2)
end

-- Toggle RTX HDR dynamically
local function toggle_hdr()
    autohdr_enabled = not autohdr_enabled
    apply_filters()
    mp.osd_message("RTX HDR (SDR->HDR) " .. (autohdr_enabled and "ON" or "OFF"), 2)
end

-- Show full status info on screen
local function show_status()
    local vsr_status = autovsr_enabled and "ON" or "OFF"
    local hdr_status = autohdr_enabled and "ON" or "OFF"
    local vf_chain = mp.get_property("vf", "")
    local output_csp = mp.get_property("d3d11-output-csp", "")
    local vo = mp.get_property("vo", "")
    local gpu_api = mp.get_property("gpu-api", "")
    local hwdec = mp.get_property("hwdec-current", "")
    local active_filters = ""

    if vf_chain:find("scaling%-mode=nvidia") then
        active_filters = active_filters .. "VSR "
    end
    if vf_chain:find("nvidia%-true%-hdr") then
        active_filters = active_filters .. "RTX-HDR "
    end
    if active_filters == "" then
        active_filters = "None"
    end

    local primaries = mp.get_property("video-params/primaries", "")
    local gamma = mp.get_property("video-params/gamma", "")
    local content_type = "SDR"
    if primaries == "bt.2020" or gamma == "pq" or gamma == "hlg" then
        content_type = "HDR (Native)"
    end

    local video_width = mp.get_property_number("width", 0)
    local video_height = mp.get_property_number("height", 0)
    local display_width = mp.get_property_number("display-width", 0)
    local display_height = mp.get_property_number("display-height", 0)
    local scale = 1
    if video_width > 0 and video_height > 0 then
        scale = math.max(display_width / video_width, display_height / video_height)
        scale = math.floor(scale * 10) / 10
    end

    mp.osd_message(
        "RTX Enhancements Status:\n" ..
        "-------------------------------\n" ..
        "RTX VSR (Upscaler): " .. vsr_status .. " (Scale: " .. scale .. "x)\n" ..
        "RTX HDR (SDR->HDR): " .. hdr_status .. "\n" ..
        "Original Content:   " .. content_type .. "\n" ..
        "Active Processing:  " .. active_filters .. "\n" ..
        "Output CSP Mode:    " .. output_csp .. "\n" ..
        "Engine details:\n" ..
        "  - VO: " .. vo .. "\n" ..
        "  - GPU API: " .. gpu_api .. "\n" ..
        "  - Decoder: " .. hwdec .. "\n" ..
        "Filter Chain: " .. (vf_chain ~= "" and vf_chain or "None"),
        5
    )
end

-- Automatically trigger filters on file load
mp.register_event("file-loaded", function()
    if autovsr_enabled or autohdr_enabled then
        -- Minor delay to ensure codec context and display properties are fully populated
        mp.add_timeout(0.2, function()
            apply_filters()
        end)
    end
end)

-- Default Hotkeys
mp.add_key_binding("ctrl+shift+r", "autovsr_toggle", toggle_vsr)
mp.add_key_binding("ctrl+shift+h", "autohdr_toggle", toggle_hdr)
mp.add_key_binding("ctrl+shift+s", "rtx_status_display", show_status)

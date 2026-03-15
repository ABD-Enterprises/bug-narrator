import os

app_path = defines["app_path"]
background_path = defines["background_path"]
volume_icon_path = defines["volume_icon_path"]

app_name = os.path.basename(app_path)

format = "UDZO"
filesystem = "HFS+"

files = [app_path]
symlinks = {"Applications": "/Applications"}

icon = volume_icon_path
background = background_path
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
label_pos = "bottom"
text_size = int(defines.get("text_size", 16))
icon_size = int(defines.get("icon_size", 148))
window_rect = (
    (int(defines.get("window_left", 180)), int(defines.get("window_top", 120))),
    (int(defines.get("window_width", 680)), int(defines.get("window_height", 420))),
)

icon_locations = {
    app_name: (int(defines.get("app_icon_x", 170)), int(defines.get("app_icon_y", 190))),
    "Applications": (
        int(defines.get("applications_icon_x", 510)),
        int(defines.get("applications_icon_y", 190)),
    ),
}

hide = [".VolumeIcon.icns", ".background.png"]

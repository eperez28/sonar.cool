# Used by dmgbuild; app and background are supplied with -D arguments.
files = [defines['app']]
symlinks = {'Applications': '/Applications'}
background = defines['background']
format = 'UDZO'
window_rect = ((160, 160), (660, 460))
icon_size = 96
text_size = 14
icon_locations = {'Sonar.app': (170, 200), 'Applications': (490, 200)}
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None

# rofi-systemd

rofi-systemd provides a menu that allows you to control systemd units in both
the user and system sessions.

## Installation

The only dependencies of rofi-systemd are rofi, systemd, awk, jq and column.

## Logs

To display logs using journalctl when rofi-systemd is not started from a tty,
you will also need some type of terminal application. RXVT unicode is used as
the default terminal for this purpose, but you can change this default by
setting the `ROFI_SYSTEMD_TERM` environment variable.

## Default action

The default behavior of rofi-systemd is to pop up a menu of actions once a unit
has been selected. This can be changed by setting `ROFI_SYSTEMD_DEFAULT_ACTION`
to a different action, i.e. one of:
 - enable
 - disable
 - stop
 - restart
 - tail
 - list_actions

## Keybindings

You can trigger an action other than the default action by using the following keybindings:
 - enable="Alt+e"
 - disable="Alt+d"
 - stop="Alt+k"
 - restart="Alt+r"
 - tail="Alt+t"

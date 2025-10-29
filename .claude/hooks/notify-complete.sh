#!/bin/bash

# Timestamp
TIMESTAMP=$(date "+%H:%M:%S")

# Notificación simple y funcional
osascript -e "display notification \"Tarea completada a las $TIMESTAMP\" with title \"🤖 Claude Code\" sound name \"Glass\""

exit 0
#!/bin/bash

# Auto-format hook para Django (Python) + React (JS/JSX)
# Se ejecuta después de que Claude edita archivos

# Leer el file_path del JSON de entrada
FILE_PATH=$(jq -r '.tool_input.file_path // .tool_input.path // empty')

# Si no hay file_path, salir silenciosamente
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Solo procesar si el archivo existe
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Obtener la extensión del archivo
EXT="${FILE_PATH##*.}"

# Formatear según el tipo de archivo
case "$EXT" in
    py)
        # Backend: Python con Black
        if command -v black &> /dev/null; then
            black "$FILE_PATH" --quiet 2>/dev/null
            echo "✓ Formatted with Black: $(basename "$FILE_PATH")"
        elif command -v ruff &> /dev/null; then
            ruff format "$FILE_PATH" --silent 2>/dev/null
            echo "✓ Formatted with Ruff: $(basename "$FILE_PATH")"
        fi
        ;;
    
    js|jsx|ts|tsx)
        # Frontend: JavaScript/React con Prettier
        if command -v prettier &> /dev/null; then
            prettier --write "$FILE_PATH" --log-level silent 2>/dev/null
            echo "✓ Formatted with Prettier: $(basename "$FILE_PATH")"
        elif command -v npx &> /dev/null; then
            npx prettier --write "$FILE_PATH" --log-level silent 2>/dev/null
            echo "✓ Formatted with Prettier: $(basename "$FILE_PATH")"
        fi
        ;;
    
    css|json|html)
        # Otros archivos frontend
        if command -v prettier &> /dev/null; then
            prettier --write "$FILE_PATH" --log-level silent 2>/dev/null
            echo "✓ Formatted with Prettier: $(basename "$FILE_PATH")"
        fi
        ;;
esac

exit 0
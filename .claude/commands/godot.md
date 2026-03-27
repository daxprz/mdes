# Godot

Control the running Godot instance.

## Sub-commands

### restart

Kill and relaunch Godot, wait for RCON to respond.

```bash
pkill -f "Godot.*test123" 2>/dev/null
sleep 1
nohup /Applications/Godot.app/Contents/MacOS/Godot --path /Users/jeremy/dev/dax/test123 > /tmp/godot_debug.log 2>&1 &
sleep 3
echo "status" | nc -w2 localhost 9999
```

Report the status response when ready.

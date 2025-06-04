## Plan for run_invenio.sh Enhancement

Here's the complete plan based on our discussion:

### 1. New Command-Line Flags
- `--stop`: Stop InvenioRDM process only (containers keep running)
- `--stop-all`: Stop InvenioRDM process + all containers (preserve data/volumes)
- `--restart`: Stop everything, then restart with same options
- `--status`: Show detailed status of InvenioRDM process and all containers

### 2. File Storage Fix
- Change default location from `/tmp/data` to `./instance/files/`
- Make configurable via `INVENIO_FILES_LOCATION` environment variable
- Auto-create directory if it doesn't exist
- Update initialization command accordingly

### 3. Repository Management
- Add `.gitignore` entries for `instance/` and other common InvenioRDM files

### 4. Process Management
- Improve PID file handling for graceful shutdowns
- Add proper cleanup of log files and temp files
- Integrate with existing Docker Compose commands

## Edit Instructions

Would you like me to proceed with implementing these changes? I'll provide specific edit instructions for:
1. Adding the new flag handling logic
2. Implementing the stop/restart functions
3. Creating the detailed status function
4. Fixing the file storage location issue
5. Adding .gitignore entries

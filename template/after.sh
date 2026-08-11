echo "Waiting for the Equine Cough Detector UI to open port ${SERVER_PORT}..."

# `wait_until_port_used`, `host`, `SCRIPT_PID` and `clean_up` come from the
# batch_connect "basic" template.
#
# 300s, not the usual 120s: on a node with a cold page cache the job first has
# to pull the ~4.7 GB Apptainer image off GPFS before Streamlit binds the port.
# A tighter budget turns a slow-but-healthy start into a "timed out" failure.
if wait_until_port_used "${host}:${SERVER_PORT}" 300; then
  echo "Server is listening on port ${SERVER_PORT}!"
else
  echo "Timed out waiting for server on port ${SERVER_PORT}."
  pkill -P "${SCRIPT_PID}"
  clean_up 1
fi

# Brief settle time before the reverse proxy connects.
sleep 2

import requests
import time
from datetime import datetime

# --- CONFIGURATION ---
LLAMA_SERVER_URL = "http://localhost:8080"
CLEANUP_THRESHOLD_SECONDS = 4800  # N seconds
POLLING_INTERVAL = 60            # How often to check the server (seconds)
# ---------------------

# This dictionary acts as our internal stopwatch.
# Format: { slot_id : timestamp_of_last_activity }
slot_tracker = {}

def get_timestamp():
    return datetime.now().strftime('%H:%M:%S')

def cleanup_slots():
    slots_url = f"{LLAMA_SERVER_URL}/slots"
    
    try:
        print(f"[{get_timestamp()}] 📡 Polling {slots_url}...")
        response = requests.get(slots_url)
        response.raise_for_status()
        slots = response.json()
        
        current_time = time.time()
        print(f"[{get_timestamp()}] 🔍 Found {len(slots)} total slots.")

        for slot in slots:
            # Safely grab the slot ID (Fallback to None if missing)
            slot_id = slot.get('id')
            if slot_id is None:
                continue
                
            is_processing = slot.get('is_processing', False)

            # 1. Initialize tracking if we've never seen this slot before
            if slot_id not in slot_tracker:
                print(f"[{get_timestamp()}] 🆕 Discovered Slot {slot_id}. Starting tracking.")
                slot_tracker[slot_id] = current_time

            # 2. Check if it's currently active
            if is_processing:
                print(f"[{get_timestamp()}] 🟢 Slot {slot_id} is ACTIVE. Resetting its timer.")
                slot_tracker[slot_id] = current_time
            
            # 3. If it's idle, calculate for how long
            else:
                idle_duration = current_time - slot_tracker[slot_id]
                print(f"[{get_timestamp()}] 🟡 Slot {slot_id} is IDLE for {int(idle_duration)}s (Threshold: {CLEANUP_THRESHOLD_SECONDS}s)")

                # 4. Trigger cleanup if threshold is exceeded
                if idle_duration > CLEANUP_THRESHOLD_SECONDS:
                    print(f"[{get_timestamp()}] 🔴 Slot {slot_id} exceeded idle threshold! Sending erase command...")
                    
                    # 'erase' is usually the standard command to clear a slot's KV cache
                    control_url = f"{LLAMA_SERVER_URL}/slots/{slot_id}?action=erase"
                    
                    try:
                        res = requests.post(control_url)
                        print(f"[{get_timestamp()}] 🧹 Action sent to Slot {slot_id}. Server responded with HTTP {res.status_code}")
                        
                        # Reset the timer so we don't spam the server while it clears
                        slot_tracker[slot_id] = current_time
                        
                    except Exception as e:
                        print(f"[{get_timestamp()}] ❌ Failed to erase slot {slot_id}: {e}")

        print("-" * 50) # Just a separator for readability in the console

    except requests.exceptions.ConnectionError:
        print(f"[{get_timestamp()}] ⚠️ Error: Could not connect to llama-server at {LLAMA_SERVER_URL}. Is it running?")
        print("-" * 50)
    except Exception as e:
        print(f"[{get_timestamp()}] ⚠️ An unexpected error occurred: {e}")
        print("-" * 50)

if __name__ == "__main__":
    print("==================================================")
    print(f"🚀 Starting Stateful Slot Cleaner")
    print(f"⚙️  Threshold: {CLEANUP_THRESHOLD_SECONDS}s | Polling: {POLLING_INTERVAL}s")
    print("==================================================")
    
    while True:
        cleanup_slots()
        time.sleep(POLLING_INTERVAL)

#!/bin/bash

# OMR App - Run with Supabase configuration
# This script runs the Flutter app with the required environment variables

flutter run \
  --dart-define=SUPABASE_URL="https://uhsshkdbuarrkyixlniz.supabase.co" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="sb_publishable_Za59Gqhn7LjOH-Oq7PK6LA_k3fpfxxC"

#!/usr/bin/env python3
"""
Auto-download images from Pexels and create a Pin on Pinterest.
Configuration via environment variables:
  PEXELS_API_KEY
  PINTEREST_ACCESS_TOKEN
  PINTEREST_BOARD_ID
Optional:
  IMGUR_CLIENT_ID - if set the script will upload downloaded images to Imgur and use that URL
Usage:
  pip install requests
  export PEXELS_API_KEY=...
  export PINTEREST_ACCESS_TOKEN=...
  export PINTEREST_BOARD_ID=...
  python upload_pexels_to_pinterest.py --query "nature" --count 1
"""
import os
import sys
import argparse
import requests
import time

PEXELS_API_KEY = os.getenv("PEXELS_API_KEY")
PINTEREST_ACCESS_TOKEN = os.getenv("PINTEREST_ACCESS_TOKEN")
PINTEREST_BOARD_ID = os.getenv("PINTEREST_BOARD_ID")
IMGUR_CLIENT_ID = os.getenv("IMGUR_CLIENT_ID")

HEADERS_PEXELS = {"Authorization": PEXELS_API_KEY} if PEXELS_API_KEY else {}

PEXELS_SEARCH_URL = "https://api.pexels.com/v1/search"
PINTEREST_PINS_URL = "https://api.pinterest.com/v5/pins"
IMGUR_UPLOAD_URL = "https://api.imgur.com/3/image"

def search_pexels(query, per_page=1):
    params = {"query": query, "per_page": per_page}
    r = requests.get(PEXELS_SEARCH_URL, headers=HEADERS_PEXELS, params=params, timeout=30)
    r.raise_for_status()
    return r.json().get("photos", [])

def download_file(url, dest_path):
    r = requests.get(url, stream=True, timeout=60)
    r.raise_for_status()
    with open(dest_path, "wb") as f:
        for chunk in r.iter_content(chunk_size=8192):
            if not chunk:
                break
            f.write(chunk)
    return dest_path

def upload_to_imgur(filepath):
    if not IMGUR_CLIENT_ID:
        raise RuntimeError("IMGUR_CLIENT_ID not set")
    headers = {"Authorization": f"Client-ID {IMGUR_CLIENT_ID}"}
    with open(filepath, "rb") as f:
        r = requests.post(IMGUR_UPLOAD_URL, headers=headers, files={"image": f}, timeout=60)
    r.raise_for_status()
    data = r.json()
    if not data.get("success"):
        raise RuntimeError(f"Imgur upload failed: {data}")
    return data["data"]["link"]

def create_pin(image_url, title, description, alt_text=None):
    if not PINTEREST_ACCESS_TOKEN or not PINTEREST_BOARD_ID:
        raise RuntimeError("PINTEREST_ACCESS_TOKEN or PINTEREST_BOARD_ID not set")
    payload = {
        "board_id": PINTEREST_BOARD_ID,
        "title": title,
        "description": description,
        "media_source": {
            "source_type": "image_url",
            "url": image_url
        }
    }
    if alt_text:
        payload["alt_text"] = alt_text
    headers = {
        "Authorization": f"Bearer {PINTEREST_ACCESS_TOKEN}",
        "Content-Type": "application/json"
    }
    r = requests.post(PINTEREST_PINS_URL, json=payload, headers=headers, timeout=30)
    r.raise_for_status()
    return r.json()

def main():
    parser = argparse.ArgumentParser(description="Download from Pexels and post to Pinterest")
    parser.add_argument("--query", required=True, help="Search query for Pexels")
    parser.add_argument("--count", type=int, default=1, help="Number of items to fetch")
    parser.add_argument("--use-hosting", action="store_true",
                        help="Download then upload to Imgur (requires IMGUR_CLIENT_ID). If not set, uses Pexels image URL directly.")
    parser.add_argument("--include-attribution", action="store_true",
                        help="Append photographer and Pexels link to pin description")
    args = parser.parse_args()

    photos = search_pexels(args.query, per_page=args.count)
    if not photos:
        print("No photos found.", file=sys.stderr)
        sys.exit(1)
    for i, p in enumerate(photos, 1):
        photographer = p.get("photographer")
        pexels_url = p.get("url")  # page url
        src = p.get("src", {})
        image_url = src.get("original") or src.get("large") or src.get("medium")
        if not image_url:
            print("No usable image src found for photo", p.get("id"), file=sys.stderr)
            continue

        final_image_url = image_url
        if args.use_hosting:
            local_name = f"pexels_{p.get('id')}.jpg"
            print("Downloading", image_url)
            download_file(image_url, local_name)
            print("Uploading to Imgur...")
            final_image_url = upload_to_imgur(local_name)
            print("Imgur URL:", final_image_url)
            try:
                os.remove(local_name)
            except Exception:
                pass

        title = f"Pexels: {p.get('id')}"
        description = p.get("alt") or p.get("photographer") or ""
        if args.include_attribution:
            description += f"\n\nPhoto by {photographer} on Pexels: {pexels_url}"

        print(f"Creating pin {i}/{len(photos)} with image {final_image_url} ...")
        resp = create_pin(final_image_url, title, description, alt_text=p.get("alt"))
        print("Pin created:", resp.get("id"))
        time.sleep(1)

if __name__ == "__main__":
    main()
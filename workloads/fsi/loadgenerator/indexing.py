#!/usr/bin/env python3
import csv
import json
import os
import uuid
from datetime import datetime
from opensearchpy import OpenSearch, helpers
from urllib.parse import urlparse

# OpenSearch connection via single ES_SERVER env var
ES_SERVER = os.getenv("ES_SERVER", "http://opensearch:9200")
parsed = urlparse(ES_SERVER)

if parsed.username and parsed.password:
    es_client = OpenSearch(
        f"{parsed.scheme}://{parsed.hostname}:{parsed.port or 9200}",
        http_auth=(parsed.username, parsed.password),
        verify_certs=False
    )
else:
    es_client = OpenSearch(ES_SERVER, verify_certs=False)

ES_INDEX = os.getenv("ES_INDEX", "locust-results")
csv_file = "/tmp/locust-results_stats.csv"

def csv_to_json(csv_path):
    """Read CSV and yield JSON objects."""
    combined = {}
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            name = row.get("Name", f"row_{len(combined)}")

            # Handle endpoint naming
            if name == "/":
                name = "home"          # rename "/" to "home"
            elif name.startswith("/"):
                name = name[1:]        # strip leading slash for other endpoints

            # Convert numeric fields from string to float/int
            for key in row:
                try:
                    if "." in row[key]:
                        row[key] = float(row[key])
                    else:
                        row[key] = int(row[key])
                except (ValueError, TypeError):
                    pass

            combined[name] = row
    return combined

def index_to_es(doc):
    """Index a single document to OpenSearch."""
    # Add UUID and @timestamp
    doc["uuid"] = os.environ.get("UUID", str(uuid.uuid4()))
    doc["timestamp"] = datetime.utcnow().isoformat()

    json_doc = json.dumps(doc, indent=2)
    print("Indexing combined document:\n", json_doc)
    es_client.index(index=ES_INDEX, body=doc)
    print(f"Indexed combined document to {ES_INDEX}")

if __name__ == "__main__":
    combined_doc = csv_to_json(csv_file)
    if combined_doc:
        index_to_es(combined_doc)
    else:
        print("No data to index")


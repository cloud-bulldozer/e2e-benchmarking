#!/usr/bin/env python3
import yaml
from collections import defaultdict
import csv
import argparse
import datetime
import os
import re
from oauth2client.service_account import ServiceAccountCredentials
import gspread
from gspread_formatting import *

regexp = re.compile(r"^\D*(\d+)\D*$")

# Globals
main_metric_rps = {"passthrough": "avg(requests_per_second)", "reencrypt": "avg(requests_per_second)", "http": "avg(requests_per_second)", "edge": "avg(requests_per_second)", "mix": "avg(requests_per_second)"}
label_map = {"passthrough": "passthrough", "reencrypt": "reencrypt", "http": "http", "edge": "edge", "mix": "mix"}
main_metric_latency = {"passthrough": "avg(latency_95pctl)", "reencrypt": "avg(latency_95pctl)", "http": "avg(latency_95pctl)", "edge": "avg(latency_95pctl)", "mix": "avg(latency_95pctl)"}

def get_uuid_mapping(file_name):
    uuid_map = {}
    uuid_titles = []
    with open(file_name, "r") as f:
        for line in f.readlines():
            if not uuid_titles:
                uuid_titles = [title.strip() for title in line.split(",")]
                continue
            uuids = line.split(",")
            for i, title in enumerate(uuid_titles):
                uuid_map[uuids[i].strip()] = title
    return uuid_map, uuid_titles


def read_yaml(yaml_files):
    data = {}
    for yaml_file in yaml_files:
        with open(yaml_file) as f:
            match = regexp.match(yaml_file)
            data[match.group(1) if match else yaml_file] = yaml.load(f, Loader=yaml.FullLoader)
    return data


def create_table_mappings(data, uuid_map, metric_map):
    tables = {}
    for file_num, datum in data.items():
        for test_type in datum["test_type"]:
            for routes in datum["test_type"][test_type]["routes"]:
                for cpt in datum["test_type"][test_type]["routes"][routes]["conn_per_targetroute"]:
                    for keepalive in datum["test_type"][test_type]["routes"][routes]["conn_per_targetroute"][cpt]["keepalive"]:
                        level_dict = datum["test_type"][test_type]["routes"][routes]["conn_per_targetroute"][cpt]["keepalive"][keepalive]
                        table = tables.setdefault((routes, label_map[test_type], cpt), defaultdict(lambda: defaultdict(dict)),)
                        if metric_map == "rps":
                            for uuid in level_dict[main_metric_rps[test_type]]:
                                table[file_num][f"{keepalive}"][uuid_map[uuid]] = level_dict[main_metric_rps[test_type]][uuid]
                        else:
                            for uuid in level_dict[main_metric_latency[test_type]]:
                                table[file_num][f"{keepalive}"][uuid_map[uuid]] = level_dict[main_metric_latency[test_type]][uuid]
    return tables


def write_to_csv(
    table_dictionary, uuid_titles, metric_write, extract_thread_count=None, result_csv_file="results.csv"):
    with open(result_csv_file, "a+") as csv_file:
        w = csv.writer(csv_file, quotechar="'")
        if metric_write == "rps":
            w.writerow(["Requests per Second"])
        else:
            w.writerow(["Latency_95Pctl (milliseconds)"])
        for key in table_dictionary.keys():
            if not extract_thread_count or (extract_thread_count and key[2] == extract_thread_count):
                w.writerow([f"{key[0]} {key[1]} routes - {key[2]} parallel conns per route"])
                header_row = [
                    "Number of Keepalive Messages",
                    *uuid_titles,
                ]
                if len(uuid_titles) == 2:
                    w.writerow(header_row + [" ", "Percent Change", "P/F"])
                else:
                    w.writerow(header_row)
                for file_num in table_dictionary[key].keys():
                    for cpt, value in table_dictionary[key][file_num].items():
                        row = [cpt] + [value.get(k, "NaN") for k in uuid_titles]
                        row.append(" ")
                        if len(uuid_titles) == 2:
                            row.append("%.1f%%" % percent_change(float(row[-2]), float(row[-3])))
                            if "latency" in metric_write.lower():
                                row.append(get_pass_fail(float(row[-3]), float(row[-4]), int(params.latency_tolerance[0]), ltcy_flag=True,))
                            else:
                                row.append(get_pass_fail(float(row[-3]), float(row[-4]), int(params.throughput_tolerance[0]), ltcy_flag=False,))
                        w.writerow(row)
                w.writerow([])
        w.writerow([])
        w.writerow([])

 
def percent_change(value, reference):
    if reference:
        return ((value - reference) * 1.0 / reference) * 100
    else:
        return -1


def get_pass_fail(val, ref, tolerance, ltcy_flag=False):
    percent_diff = abs(percent_change(val, ref))
    if val < ref and percent_diff > tolerance:
        if ltcy_flag:
            return "Pass"
        else:
            return "Fail"
    elif val > ref and percent_diff > tolerance:
        if ltcy_flag:
            return "Fail"
        else:
            return "Pass"
    else:
        return "Pass"


def generate_csv(params, result_csv_file="results.csv", extract_keepalive=None):
    uuid_map = {}
    uuid_titles = []
    for position, uuid in enumerate(params.uuids):
        try:
            uuid_map[uuid] = params.prefix[position]
            uuid_titles.append(params.prefix[position])
        except IndexError:
            uuid_map[uuid] = uuid
            uuid_titles.append(uuid)
    data = read_yaml(params.yaml_files)
    metric_type = ["rps", "latency"]
    for metric in metric_type:
        tables = create_table_mappings(data, uuid_map, metric_map=metric)
        write_to_csv(tables, uuid_titles, metric, extract_keepalive, result_csv_file)
    print(f"Test Completed!\n\tResults file generated -> {params.sheetname}.csv")


def push_to_gsheet(csv_file_name, google_svc_acc_key, email_id):
    fmt = cellFormat(
        # backgroundColor=color(1, 0.9, 0.9),
        # textFormat=textFormat(bold=True, foregroundColor=color(1, 0, 1)),
        horizontalAlignment="RIGHT"
    )
    scope = [
        "https://spreadsheets.google.com/feeds",
        "https://www.googleapis.com/auth/drive",
    ]
    credentials = ServiceAccountCredentials.from_json_keyfile_name(google_svc_acc_key, scope)
    gc = gspread.authorize(credentials)

    sh = gc.create(params.sheetname)  # Specify name of the Spreadsheet
    sh.share(email_id, perm_type="user", role="writer")
    spreadsheet_id = sh.id
    spreadsheet_url = f"https://docs.google.com/spreadsheets/d/{sh.id}"
    with open(csv_file_name, "r") as f:
        gc.import_csv(spreadsheet_id, f.read())
    worksheet = sh.get_worksheet(0)
    format_cell_range(worksheet, "1:1000", fmt)
    set_column_width(worksheet, "A", 290)
    print(f"            Google Spreadsheet link -> {spreadsheet_url}\n")


# Main
now = datetime.datetime.today()
timestamp = now.strftime("%Y-%m-%d-%H.%M.%S")
parser = argparse.ArgumentParser()
parser.add_argument("--sheetname", help="Google Spreadsheet name",
                    default=f"Router-Test-Results-{str(timestamp)}")
parser.add_argument("-f", "--files", help="YAML files to scrape output from", nargs="+", required=True,
                    dest="yaml_files",)
parser.add_argument("-l", "--latency_tolerance", help="Accepted deviation (+/-) from the reference result",
                    required=False, default="5")
parser.add_argument("-t", "--throughput_tolerance", help="Accepted deviation (+/-) from the reference result",
                    required=False, default="5")
parser.add_argument("-u", "--uuids", help="""List of UUID to compare, if two uuids are passed first one will 
                                             be used as baseline""", required=True, nargs="+")
parser.add_argument("-p", "--prefix", help="Test prefix list", required=True, nargs="+")
params = parser.parse_args()
if len(params.uuids) > 2:
    print("The maximum number of to compare UUIDs is two")
    exit(1)
generate_csv(params, f"{params.sheetname}.csv")
if "EMAIL_ID_FOR_RESULTS_SHEET" and "GSHEET_KEY_LOCATION" in os.environ:
    push_to_gsheet(
        f"{params.sheetname}.csv", os.environ["GSHEET_KEY_LOCATION"], os.environ["EMAIL_ID_FOR_RESULTS_SHEET"],
    )

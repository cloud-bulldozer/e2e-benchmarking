#!/usr/bin/python3
import csv
import argparse
import os
from oauth2client.service_account import ServiceAccountCredentials
import gspread
from gspread_formatting import *

START_END_ROW_PAIRS_OTHER = [(1, 11), (15, 25), (29, 39), (43, 53)]
START_END_ROW_PAIRS_HOSTNET = [(1, 5), (9, 13), (17, 21), (25, 29)]

parser = argparse.ArgumentParser()
parser.add_argument(
    "--gid",
    help="grid id (gid)",
    nargs=1,
    required=True,
    dest="gid",
)
parser.add_argument(
    "--spreadsheet-url",
    help="Spreadsheet URL",
    nargs=1,
    required=True,
    dest="spreadsheet_url",
)
params = parser.parse_args()
scope = [
    "https://spreadsheets.google.com/feeds",
    "https://www.googleapis.com/auth/drive",
]
credentials = ServiceAccountCredentials.from_json_keyfile_name(
    "/root/.secrets/gsheet_key.json", scope
)
gc = gspread.authorize(credentials)
sh = gc.open_by_url(params.spreadsheet_url[0])
sourceSheetId = params.gid[0]


def create_chart(title, x_axis, y_axis, startRowIndex, endRowIndex):
    body = {
        "requests": [
            {
                "addChart": {
                    "chart": {
                        "spec": {
                            "title": title,
                            "basicChart": {
                                "chartType": "COLUMN",
                                "legendPosition": "BOTTOM_LEGEND",
                                "axis": [
                                    {"position": "BOTTOM_AXIS", "title": x_axis},
                                    {"position": "LEFT_AXIS", "title": y_axis},
                                ],
                                "domains": [
                                    {
                                        "domain": {
                                            "sourceRange": {
                                                "sources": [
                                                    {
                                                        "sheetId": sourceSheetId,
                                                        "startRowIndex": startRowIndex,
                                                        "endRowIndex": endRowIndex,
                                                        "startColumnIndex": 0,
                                                        "endColumnIndex": 1,
                                                    }
                                                ]
                                            }
                                        }
                                    }
                                ],
                                "series": [
                                    {
                                        "series": {
                                            "sourceRange": {
                                                "sources": [
                                                    {
                                                        "sheetId": sourceSheetId,
                                                        "startRowIndex": startRowIndex,
                                                        "endRowIndex": endRowIndex,
                                                        "startColumnIndex": 1,
                                                        "endColumnIndex": 2,
                                                    }
                                                ]
                                            }
                                        },
                                        "targetAxis": "LEFT_AXIS",
                                    },
                                    {
                                        "series": {
                                            "sourceRange": {
                                                "sources": [
                                                    {
                                                        "sheetId": sourceSheetId,
                                                        "startRowIndex": startRowIndex,
                                                        "endRowIndex": endRowIndex,
                                                        "startColumnIndex": 2,
                                                        "endColumnIndex": 3,
                                                    }
                                                ]
                                            }
                                        },
                                        "targetAxis": "LEFT_AXIS",
                                    },
                                ],
                                "headerCount": 1,
                            },
                        },
                        "position": {"newSheet": "true"},
                    }
                }
            }
        ]
    }
    sh.batch_update(body)


if os.environ["WORKLOAD"] == "hostnet":
    create_chart(
        "TCP Latency",
        "Message Size(Bytes)-Number of client server pairs",
        "microseconds",
        *START_END_ROW_PAIRS_HOSTNET[0]
    )
    create_chart(
        "UDP Latency",
        "Message Size(Bytes)-Number of client server pairs",
        "microseconds",
        *START_END_ROW_PAIRS_HOSTNET[1]
    )
    create_chart(
        "TCP Throughput",
        "Message Size(Bytes)-Number of client server pairs",
        "Mbits/s",
        *START_END_ROW_PAIRS_HOSTNET[2]
    )
    create_chart(
        "UDP Throughput",
        "Message Size(Bytes)-Number of client server pairs",
        "Mbits/s",
        *START_END_ROW_PAIRS_HOSTNET[3]
    )
else:
    create_chart(
        "TC Latency",
        "Message Size(Bytes)-Number of client server pairs",
        "microseconds",
        *START_END_ROW_PAIRS_OTHER[0]
    )
    create_chart(
        "UDP Latency",
        "Message Size(Bytes)-Number of client server pairs",
        "microseconds",
        *START_END_ROW_PAIRS_OTHER[1]
    )
    create_chart(
        "TCP Throughput",
        "Message Size(Bytes)-Number of client server pairs",
        "Mbits/s",
        *START_END_ROW_PAIRS_OTHER[2]
    )
    create_chart(
        "UDP Throughput",
        "Message Size(Bytes)-Number of client server pairs",
        "Mbits/s",
        *START_END_ROW_PAIRS_OTHER[3]
    )

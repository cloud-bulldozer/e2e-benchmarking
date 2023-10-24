from datetime import datetime, timedelta
import numpy as np
import pandas as pd
from search import ElasticService


def pd_merge(previous_data, current_data, columns):
    """ 
    Merge the previous data frame with current data frame by last column 

    Args:
        previous_data DataFrame: Previous data, dataframe 
        current_data DataFrame: Current data, dataframe 
        columns list[str]: Column titles 

    Returns:
        DataFrame: Merged previous and current data frame
    """
    pd_merged = current_data.merge(previous_data, how="outer", on=columns[:-1])
    return pd_merged


def find_result(row, tolerancy):
    """
    Find if row difference is higher or lower than given tolerancy
    Fail if difference is more negative than tolerany and
        if difference is higher than tolerancy

    Args:
        row: Row of data frame to give pass/fail value of difference
        tolerancy: amount difference we want to pass/fail on 

    Returns:
        Pass or Fail: if difference is greater than tolerancy
    """
    if np.isinf(row["difference"]):
        return "Pass"
    # Fail if value is a more negative than tolerancy
    if row["difference"] < 0 and tolerancy > row["difference"]:
        return "Fail"
    elif row["difference"] > 0 and tolerancy > row["difference"]:
        return "Fail"
    else:
        return "Pass"


def tolerancy(all_data_points, tolerancy_percent):
    """
    Find the percent difference in last 2 columns of each row
    Give this number as a percent change and generate pass/fail on value

    Args:
        all_data_points DataFrame: Data frame of all previous and current data points
        tolerancy_percent int: number to determine pass/fail rate on 

    Returns:
        DataFrame: All data points with percent difference and pass/fail column
    """
    print("tolerancy " + str(all_data_points))
    all_data_points.fillna(method="ffill")

    result = all_data_points.iloc[:, [-2, -1]].pct_change(axis=1).iloc[:, 1] * 100

    all_with_result = all_data_points.assign(difference=result)

    all_with_result["result"] = all_with_result.apply(
        lambda row: find_result(row, tolerancy_percent), axis=1
    )

    return all_with_result


def process_all_data(
    metric_of_interest,
    find_metrics,
    uuid,
    ids,
    data_func,
    index,
    divider,
    additional_columns,
):
    """
    Main function to get current and past data based on specific metric indicators

    Args:
        metric_of_interest (str): name of the metric that we want to compare on 
        find_metrics (dict): metric dict to put in data frame columns and filter on
        uuid (str): uuid to get data on 
        ids (list): list of other matching uuids to compare against
        data_func (str): type of function to combine previous data points (max or avg)
        index (str): elastic search index to search for the data points in
        divider (int): if you want to divide the metric_of_interest by a set int
        additional_columns (list): data columns to combine similar data on but not filter out any specific data points

    Returns:
        oMetrics: past data frame 
        nMetrics: current uuid data
        columns: the column titles in the data frame
    """
    # Process all

    columns = []
    for k in find_metrics.keys():
        columns.append(k)
    for column_name in additional_columns:
        columns.append(column_name)
    columns.append(metric_of_interest)
    # Get all previous run data
    oData = getResults(uuid, ids, index, find_metrics)
    oMetrics = processData(oData, columns, data_func)

    oMetrics = oMetrics.reset_index()
    oMetrics[metric_of_interest] = oMetrics[metric_of_interest] / divider

    # Current data metrics
    cData = getResults(uuid, [uuid], index, find_metrics)
    nMetrics = processData(cData, columns, data_func)
    nMetrics = nMetrics.reset_index()
    nMetrics[metric_of_interest] = nMetrics[metric_of_interest] / divider
    return oMetrics, nMetrics, columns


def generate_pass_fail(oMetrics, nMetrics, columns, tolerancy_num):
    """
    Generae pass fail of current and past metrics based on tolerancy num

    Args:
        oMetrics (_type_): past data sset
        nMetrics (_type_): current data set
        columns (_type_): column titles to find
        tolerancy_num (_type_): tolerancy to compare within and get pass/fail

    Returns:
        dataFrame: data frame of all current and past data with tolerancy and pass/fail
    """
    if not oMetrics.empty and not nMetrics.empty:
        all_merged = pd_merge(oMetrics, nMetrics, columns)

        all_result_tolerancy = tolerancy(all_merged, tolerancy_num)
        return all_result_tolerancy
    return []


def processData(data: dict, columns: list[str], func="mean"):
    """
    Process data by creating data frame and getting mean of columns

    Args:
        data (dict): data 
        columns (list[str]): column titles 
        func (str, optional): Type of function to apply to data. Defaults to "mean".

    Returns:
        int: 
    """
    # pprint.pprint(data)
    df = pd.json_normalize(data)
    filterDF = createDataFrame(df, columns)
    if func == "avg" or func == "mean":
        ptile = filterDF.groupby(columns[:-1])[columns[-1]].mean()
    elif func == "max":
        ptile = filterDF.groupby(columns[:-1])[columns[-1]].max()
    return ptile


def jobFilter(pdata: dict, data: dict):
    """
    Filter out jobs that dont match same iterations

    Args:
        pdata (dict): data frame 
        data (dict): _description_

    Returns:
        list: list of uuids that have same iterations
    """
    columns = ["uuid", "jobConfig.jobIterations"]
    pdf = pd.json_normalize(pdata)
    pick_df = pd.DataFrame(pdf, columns=columns)
    iterations = pick_df.iloc[0]["jobConfig.jobIterations"]
    df = pd.json_normalize(data)
    ndf = pd.DataFrame(df, columns=columns)
    ids_df = ndf.loc[df["jobConfig.jobIterations"] == iterations]
    return ids_df["uuid"].to_list()


def createDataFrame(data: dict, columns: list[str]):
    """
    Create data frame from dict data and a list of columns

    Args:
        data (dict): all data collected from elastic search
        columns (list[str]): column titles

    Returns:
        DataFarme: Data frame of data with column headers
    """
    ndf = pd.DataFrame(data, columns=columns)
    print("ndf " + str(ndf))
    return ndf


def getResults(uuid: str, uuids: list, index_str: str, metrics: dict):
    """
    Get results of elasticsearch data query based on uuid(s) and defined metrics

    Args:
        uuid (str): _description_
        uuids (list): _description_
        index_str (str): _description_
        metrics (dict): _description_

    Returns:
        dict: Resulting data from query
    """
    if len(uuids) > 1 and uuid in uuids:
        uuids.remove(uuid)
    ids = '" OR uuid: "'.join(uuids)
    metric_string = ""
    for k, v in metrics.items():
        if isinstance(v,str):
            v = f'"{v}"'
        metric_string += f" AND {k}: {v}"

    
    #print('get results ' + str(ids))
    query = {
        "query": {"query_string": {"query": (f'( uuid: "{ids}" )' + metric_string)}}
    }
    print(query)
    print("index " + str(index_str))
    es = ElasticService(index=index_str)
    response = es.post(query)
    # print('respnse ' + str(response))
    es.close()
    runs = [item["_source"] for item in response["hits"]["hits"]]
    return runs


def get_past_date(str_date_ago):
    """
    Get the date string of a past date

    Args:
        str_date_ago str: String of how long ago to retrieve data 

    Returns:
        str: String of past date in formatted type 
    """
    today_now = datetime.now()
    splitted = str_date_ago.split()
    if splitted[1].lower() in ["hour", "hours", "hr", "hrs", "h"]:
        date = datetime.datetime.now() - timedelta(hours=int(splitted[0]))
    elif splitted[1].lower() in ["day", "days", "d"]:
        date = today_now - timedelta(days=int(splitted[0]))
    elif splitted[1].lower() in ["wk", "wks", "week", "weeks", "w"]:
        date = today_now - timedelta(weeks=int(splitted[0]))
    elif splitted[1].lower() in ["mon", "mons", "month", "months", "m"]:
        date = today_now - timedelta(months=int(splitted[0]))
    elif splitted[1].lower() in ["yrs", "yr", "years", "year", "y"]:
        date = today_now - timedelta(years=int(splitted[0]))
    return format_dt_string(date)


def format_dt_string(date_time_str):
    """
    Format datetime string into expected syntax

    Args:
        date_time_str (_type_): date time string variable to format

    Returns:
        str: datetime formatted into a string 
    """
    dt_string = date_time_str.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    print("date and time =", dt_string)

    return dt_string


def get_current_date_time():
    """
    Get current datetime

    Returns:
        str: current datetime formatted into a string 
    """
    # Might need utc time version
    now = datetime.now()
    print("now =" + str(now))

    return format_dt_string(now)


def get_match_runs(meta: dict, workerCount: False, previous_version=False, time_range=""):
    """
    Find matching runs to current uuid data based on cluster configuration

    Args:
        meta (dict): _description_
        workerCount (False): _description_
        previous_version (bool, optional): _description_. Defaults to False.
        time_range (str, optional): _description_. Defaults to "".

    Returns:
        _type_: _description_
    """
    index = "perf_scale_ci"
    version = meta["ocpVersion"][:4]
    if previous_version:
        version = float(version) - 0.01

    # https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-range-query.html

    params = {
        "benchmark": meta["benchmark"],
        "workerNodesType": meta["workerNodesType"],
        "clusterType": meta["clusterType"],
        "networkType": meta["networkType"],
        "platform": meta["platform"],
        "jobStatus": "success",
    }
    wildcard = {"ocpVersion": f"{version:.2f}" + "*"}

    # For hcp-rosa, there is no master node type
    if meta["masterNodesType"] != "":
        params["masterNodesType"] = meta["masterNodesType"]

    if workerCount:
        params["workerNodesCount"] = meta["workerNodesCount"]

    filter_data = []
    filter_data.append({"match_all": {}})
    for p, v in params.items():
        match_data = {}
        match_data["match_phrase"] = {}
        match_data["match_phrase"][p] = v
        filter_data.append(match_data)
    if wildcard != "":
        for p, v in wildcard.items():
            wildcard_data = {}
            wildcard_data["wildcard"] = {}
            wildcard_data["wildcard"][p] = v
            filter_data.append(wildcard_data)
    if time_range != "":
        range_json = {}
        range_json["range"] = {
            "timestamp": {
                "lte": get_current_date_time(),
                "gte": get_past_date(time_range),
                "format": "strict_date_optional_time",
            }
        }
        filter_data.append(range_json)

    query = {"query": {"bool": {"filter": filter_data}}}
    es = ElasticService(index=index)
    response = es.post(query)
    es.close()
    runs = [item["_source"] for item in response["hits"]["hits"]]
    uuids = []

    for run in runs:
        uuids.append(run["uuid"])
    # print("uuids" + str(uuids))
    return uuids


def get_metadata(uuid: str):
    """
    Get metadata details of uuids configuration

    Args:
        uuid (str): 

    Returns:
        dict: dictionary of metadata of run from uuid
    """
    index = "perf_scale_ci"
    query = {"query": {"query_string": {"query": (f'uuid: "{uuid}"')}}}
    # print(query)
    es = ElasticService(index)
    response = es.post(query)
    # print('response ' + str(response))
    es.close()
    meta = [item["_source"] for item in response["hits"]["hits"]]
    print("meta data")
    if len(meta) > 0:
        return meta[0]
    return False

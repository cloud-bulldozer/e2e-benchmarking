#!/usr/bin/env python3

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import operator
import yaml

parser = argparse.ArgumentParser()
parser.add_argument("--result",help="Touchstone result yaml file",nargs=1,required=True,
                   dest="result")
parser.add_argument("--uuid", help="UUID to determine pass/fail from",nargs=1,required=True,
                    dest="uuid")
parser.add_argument("--tests", help="Test to compare",nargs=1,choices=['stream','rr'],required=True,
                    dest="tests")
parser.add_argument("--protocol", help="Protocol to compare",nargs=1,choices=['tcp','udp'],required=True,
                    dest="protocol")
parser.add_argument("--tolerance", help="Accepted deviation (+/-) from the reference result",nargs=1,required=False,
                    dest="tolerance", default="5")

params = parser.parse_args()
data = None

if params.result :
    with open(params.result[0]) as file:
        try:
            data = yaml.load(file, Loader=yaml.FullLoader)
        except:
            print("Error : Not able to load the result file")
            exit(1)

if len(data) < 1 :
    print("YAML file contains no data")
    exit(1)

def percent_change(value, reference):
    if reference:
        return abs(((value-reference)*1.0/reference))*100
    else:
        return -1

def compare(data, tolerance, latency=False):
    ref_val = data[params.uuid[0]]
    current_tuple = [(k,v) for k,v in data.items() if k!=params.uuid[0]][0]
    percent_diff = percent_change(current_tuple[1], ref_val)
  
    if percent_diff == -1:
        return {current_tuple[0]: current_tuple[1]}

    if current_tuple[1] < ref_val and percent_diff > tolerance:
        if latency:
            return {params.uuid[0]: ref_val}
        return {current_tuple[0]: current_tuple[1]}

    elif current_tuple[1] > ref_val and percent_diff > tolerance:
        if latency:
            return {current_tuple[0]: current_tuple[1]}
        return {params.uuid[0]: ref_val}

    else:
        return {params.uuid[0]: ref_val}

main_metric = { 'stream': 'avg(norm_byte)','rr' : 'avg(norm_ltcy)' }

failed = 0
test_type = params.tests[0]
proto = params.protocol[0]

if test_type in data['test_type.keyword'] :
    if proto in data['test_type.keyword'][test_type]['protocol'] :
        for size in data['test_type.keyword'][test_type]['protocol'][
            proto]['message_size'] :
            for thread in data['test_type.keyword'][test_type]['protocol'][
                proto]['message_size'][size]['num_threads'] :
                result = data['test_type.keyword'][test_type]['protocol'][
                        proto]['message_size'][size]['num_threads'][thread]
                if test_type == "rr" :
                    comparison = compare(result[main_metric[test_type]], int(params.tolerance[0]), latency=True)
                else:
                    comparison = compare(result[main_metric[test_type]], int(params.tolerance[0]))
                if params.uuid[0] not in comparison :
                    print("TEST FAILURE: Uperf reports regrerssion which is beyond the acceptable deviation of {}%".format(params.tolerance[0]))
                    print("Test: {}    Protocol: {}    Message_size: {}    Threads: {}".format(
                        test_type,proto,size,thread))
                    failed = 1   
exit(failed)

import argparse
import getpass
import json
import logging

import requests
import sys

import urllib3

import os
import pathlib
import csv

from datetime import datetime
from pprint import pprint


def start():

    my_path = pathlib.Path(__file__).parent.resolve()
    rep_folder = os.path.join(my_path, "data_dell")
    os.makedirs(rep_folder, exist_ok=True)

    input_file = os.path.join(my_path, "input.csv")

    with open(input_file, 'r') as file:
        csvreader = csv.DictReader(file, delimiter='\t')
        for row in csvreader:
            export_hw_inventory(row["ip"], row["login"], row["password"], False, rep_folder, "hwinv_temp.xml")




def export_hw_inventory(idrac_ip, idrac_username, idrac_password, verify_cert, filepath, filename):
    global ST
    url = 'https://%s/redfish/v1/Dell/Managers/iDRAC.Embedded.1/DellLCService/Actions/DellLCService.ExportHWInventory' % idrac_ip
    method = "ExportHWInventory"

    payload = {"ShareType": "Local", "FileName": filename}

    headers = {'content-type': 'application/json'}
    response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert,
                             auth=(idrac_username, idrac_password))

    if response.status_code == 202:
        logging.info("\n- PASS: POST command passed for %s method, status code 202 returned" % method)
    else:
        logging.error("\n- FAIL, POST command failed for %s method, status code is %s" % (method, response.status_code))
        data = response.json()
        logging.error("\n- POST command failure results:")
        logging.error(data)
        sys.exit(0)

    if response.headers['Location'] == "/redfish/v1/Dell/hwinv.xml":
        response = requests.get('https://%s%s' % (idrac_ip, response.headers['Location']), verify=verify_cert,
                                auth=(idrac_username, idrac_password))
        if filename:
            export_filename = filepath + r"\\" + filename
        else:
            export_filename = "hwinv.xml"
        with open(export_filename, "wb") as output:
            output.write(response.content)

        import xml.etree.ElementTree as ET
        tree = ET.parse(export_filename)
        root = tree.getroot()
        instances = root.find("MESSAGE").find("SIMPLEREQ").findall("VALUE.NAMEDINSTANCE")
        for instance in instances:
            elem = instance.find("INSTANCE")
            if elem.get("CLASSNAME") == "DCIM_SystemView":
                for property in elem.findall("PROPERTY"):
                    if property.get("NAME") == "ChassisServiceTag":
                        ST = property.find("VALUE").text

        new_path = filepath + r"\\" + ST + ".xml"

        os.replace(export_filename, new_path)

        logging.info("\n- INFO, check your local directory for hardware inventory XML file \"%s\"" % new_path)

    else:
        logging.error(
            "- ERROR, unable to locate exported hardware inventory URI in headers output. Manually run GET on URI %s to see if file can be exported." %
            response.headers['Location'])
        sys.exit(0)


# Press the green button in the gutter to run the script.
if __name__ == '__main__':
    logging.basicConfig(format='%(message)s', stream=sys.stdout, level=logging.INFO)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    start()

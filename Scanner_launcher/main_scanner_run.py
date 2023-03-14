import argparse
import json
import logging
import multiprocessing
import os.path
import re
import sys
import requests
import hpilo

from functions import setup_logging

vers = "1.0"


def get_data_from_ip(ip, username, password):
    logger = logging.getLogger('server-scanner')
    logger.debug(f'get_data_from_ip for ip {ip}: Entering module, username "{username}", password "{password}"')

    # Check if Dell RedFish v1
    url = f'https://{ip}/redfish/v1/'
    headers = {'content-type': 'application/json'}
    try:
        response = requests.get(url, headers=headers, verify=False, auth=(username, password))
        if response.status_code == 200:
            content = json.loads(response.content)
            if content.get("Product", False) == 'Integrated Dell Remote Access Controller':
                logger.debug(f'get_data_from_ip for ip {ip}: It is iDRAC calling DELL HW collector')
                # TODO Add hw collector for DELL RedFish v1
                print(f'Dell {ip}')
                return
            elif content.get('Vendor') == 'Lenovo':
                logger.debug(f'get_data_from_ip for ip {ip}: It is XCC calling LENOVO HW collector')
                # TODO Add Lenovo collector for Redfish v1
                print(f'Lenovo {ip}')
                return
    except Exception as ex:
        logger.debug(f'get_data_from_ip for ip {ip}: Error, exception: {ex}, not DELL continue checking')

    try:
        ilo = hpilo.Ilo(ip, username, password)
        version = ilo.get_fw_version().get('management_processor')
        if version == 'iLO4':
            logger.debug(f'get_data_from_ip for ip {ip}: We are having the iLO 4, calling the script')
            # TODO Add HPE iLO4 script here
        elif version== 'iLO3':
            logger.debug(f'get_data_from_ip for ip {ip}: We are having the iLO 3, calling the script')
            # TODO Add HPE iLO3 script here
        elif version== 'iLO2':
            logger.debug(f'get_data_from_ip for ip {ip}: We are having the iLO 2, calling the script')
            # TODO Add HPE iLO2 script here
        elif version== 'iLO1':
            logger.debug(f'get_data_from_ip for ip {ip}: We are having the iLO 1, calling the script')
            # TODO Add HPE iLO1 script here
        elif version== 'iLO5':
            logger.debug(f'get_data_from_ip for ip {ip}: We are having the iLO 5, calling the script')
            # TODO Add HPE iLO5 script here


    except Exception as ex:
        logger.error(f'get_data_from_ip for ip {ip}: Error, exception: {ex}, not HPE continue checking')

    return


def get_data_from_file(file, username, password, procnum):
    logger = logging.getLogger('server-scanner')
    logger.info(f'Start parsing file with path {file}')
    logger.debug("Input params:")
    logger.debug(f'Filepath: {file}')
    logger.debug(f'Default username: {username}')
    logger.debug(f'Default password: {password}')

    def_username = username
    def_password = password

    # Read file
    task_scheduler = []
    try:
        with open(file, "r") as f:
            for line in f.readlines():
                tmp_re = re.search('^(\d+\.\d+\.\d+\.\d+),(.+),(.+)$', line)
                if tmp_re:
                    task_scheduler.append([tmp_re.group(1), tmp_re.group(2), tmp_re.group(3)])
                    continue
                tmp_re = re.search('^default,(.+),(.+)$', line)
                if tmp_re:
                    def_username = tmp_re.group(1)
                    def_password = tmp_re.group(2)
                    continue
                tmp_re = re.search('^(\d+\.\d+\.\d+\.\d+)$', line)
                if tmp_re:
                    task_scheduler.append([tmp_re.group(1), def_username, def_password])
                    continue


    except Exception as ex:
        print('Exception with file')
        print(ex)
        logger.error(f'get_data_from_file: {ex}')
        return

    # Create and initialize the working process pool
    pool = multiprocessing.Pool(processes=procnum)
    pool.starmap(get_data_from_ip, task_scheduler)
    pool.close()

    return



def main():
    # Parsing parameters
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--version', '-v', action="store_true",
        help="Version info")
    parser.add_argument(
        '--debug', '-d', action="store_true",
        help="Run in debug mode")
    parser.add_argument(
        '--username', '-u', action="store",
        help="Username for BMC module",
        default="None")
    parser.add_argument(
        '--password', '-p', action="store",
        help="Password for BMC module",
        default="None")
    parser.add_argument(
        '--ip', '-i', action="store",
        help="IP address for BMC module",
        default="None")
    parser.add_argument(
        '--file', '-f', action="store",
        help="Path to the file with IPs of BMC modules",
        default="None")
    parser.add_argument(
        '--workers', '-w', action="store",
        help="Number of workers to process the file",
        default="50")

    args = parser.parse_args()

    if args.version:
        print(vers)
        sys.exit()

    loglevel = logging.INFO
    if args.debug:
        loglevel = logging.DEBUG

    if not os.path.exists('logs'):
        os.mkdir('logs')
    logfile = os.path.join('logs', 'eventlog.log')

    setup_logging(loglevel, 10240, 4, logfile)

    logger = logging.getLogger('server-scanner')

    logger.info("Starting data collection for audit")

    if args.ip is not 'None' and args.username is not 'None' and args.password is not 'None':
        get_data_from_ip(args.ip, args.username, args.password)
        print("Success")
        print("I've got the data from IP %s" % args.ip)
        sys.exit()

    if args.file is not None:
        get_data_from_file(args.file, args.username, args.password, int(args.workers))
        print("Success")
        print("I've parsed file %s" % args.file)
        sys.exit()

    print('Wrong arguments')
    parser.print_help()



if __name__ == '__main__':
    main()
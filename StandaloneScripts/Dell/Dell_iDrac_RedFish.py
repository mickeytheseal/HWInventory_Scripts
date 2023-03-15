import sys
import csv
import json
import requests
from requests.auth import HTTPBasicAuth
from requests.adapters import HTTPAdapter

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class HWData:
	def __init__(self,vendor,sn):
		self.vendor = vendor
		self.sn = sn
		self.processors = []
		self.memory = []
		self.controllers = []
		self.drives = []
		self.psu = []
		self.pci = []

	def toJSON(self):
		json_object = json.dumps(self, default=lambda o: o.__dict__, sort_keys=True, indent=4)
		return str(json_object)


def collectData(server_ip, server_user, server_pass):

	base_url = f"https://{server_ip}"

	# Create session
	session = requests.Session()
	session.auth = HTTPBasicAuth(server_user, server_pass)
	session.verify = False

	# Get ServiceTag
	servicetag_info_url = base_url + f"/redfish/v1/"
	servicetag_info_response = session.get(servicetag_info_url)
	servicetag_info_json = servicetag_info_response.json()
	servicetag = servicetag_info_json["Oem"]["Dell"]["ServiceTag"]
	print(f"\nCollecting data from {server_ip}. ServiceTag: {servicetag}")

	srv = HWData("DELL",servicetag)

	# Get processor info
	processors_info_url = base_url + f"/redfish/v1/Systems/System.Embedded.1/Processors"
	processors_info_response = session.get(processors_info_url)
	processors_info_json = processors_info_response.json()
	for proc_socket in processors_info_json["Members"]:
		url_part = proc_socket["@odata.id"]
		processor_info_url = base_url + url_part
		processor_info_response = session.get(processor_info_url)
		processor_info_json = processor_info_response.json()
		srv.processors.append(processor_info_json["Model"])
	print("Collected CPU info")

	# Get memory info
	memory_info_url = base_url + f"/redfish/v1/Systems/System.Embedded.1/Memory"
	memory_info_response = session.get(memory_info_url)
	memory_info_json = memory_info_response.json()
	for mem_socket in memory_info_json["Members"]:
		url_part = mem_socket["@odata.id"]
		memory_info_url = base_url + url_part
		memory_info_response = session.get(memory_info_url)
		memory_info_json = memory_info_response.json()
		srv.memory.append(memory_info_json["PartNumber"])
	print("Collected Memory info")

	# Get storage info
	storage_info_url = base_url + f"/redfish/v1/Systems/System.Embedded.1/Storage"
	storage_info_response = session.get(storage_info_url)
	storage_info_json = storage_info_response.json()
	for controller in storage_info_json["Members"]:
		ctrl_part = controller["@odata.id"]
		ctrl_info_url = base_url + ctrl_part
		ctrl_info_response = session.get(ctrl_info_url)
		ctrl_info_json = ctrl_info_response.json()													
		srv.controllers.append(ctrl_info_json["Name"])
		for drive in ctrl_info_json["Drives"]:
			url_part = drive["@odata.id"]
			drive_info_url = base_url + url_part
			drive_info_response = session.get(drive_info_url)
			drive_info_json = drive_info_response.json()
			srv.drives.append(drive_info_json["Model"])
	print("Collected Storage info")

	# Get PSU info
	power_info_url = base_url + f"/redfish/v1/Chassis/System.Embedded.1/Power#"
	power_info_response = session.get(power_info_url)
	power_info_json = power_info_response.json()
	for psu in power_info_json["PowerSupplies"]:
		srv.psu.append(psu["PartNumber"])
	print("Collected PSU info")

	# Get PCI info
	chassis_info_url = base_url + f"/redfish/v1/Chassis/System.Embedded.1"
	chassis_info_response = session.get(chassis_info_url)
	chassis_info_json = chassis_info_response.json()
	for device in chassis_info_json["Links"]["PCIeDevices"]:
		url_part = device["@odata.id"]
		device_info_url = base_url + url_part
		device_info_response = session.get(device_info_url)
		device_info_json = device_info_response.json()
		srv.pci.append(str(device_info_json["Name"]) + "|" + str(device_info_json["PartNumber"]))	#TODO: Filter integrated devices
	print("Collected PCI info")

	session.close()
	srv_json = srv.toJSON()
	return srv_json, servicetag
  

def saveToFile(data,outputPath,filename):
	with open(f'{outputPath}\\{filename}.json', 'w') as f:
		f.write(data)


if __name__ == "__main__":
	inputFile = sys.argv[1]
	outputPath = sys.argv[2]
	print(inputFile)
	with open(inputFile, 'r') as csvfile:
		datareader = csv.reader(csvfile,delimiter=';')	#Change delimeter if needed
		next(datareader)
		for row in datareader:
			collectedData, filename = collectData(row[0],row[1],row[2])
			saveToFile(collectedData,outputPath,filename)

			
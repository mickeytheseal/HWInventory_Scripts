import requests
from requests.auth import HTTPBasicAuth

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Set creds for  connection
server_ip = "172.24.1.228"
server_user = "root"
server_pass = "calvin"

# Create session
session = requests.Session()
session.auth = HTTPBasicAuth(server_user, server_pass)
session.verify = False

base_url = f"https://{server_ip}"

# Get processor info
processors_info_url = base_url + f"/redfish/v1/Systems/System.Embedded.1/Processors"
processors_info_response = session.get(processors_info_url)
processors_info_json = processors_info_response.json()
print("\nCPU:")
for proc_socket in processors_info_json["Members"]:
	url_part = proc_socket["@odata.id"]
	processor_info_url = base_url + url_part
	processor_info_response = session.get(processor_info_url)
	processor_info_json = processor_info_response.json()
	print(processor_info_json["Model"])									#TODO: SaveToFile + count

# Get memory info
memory_info_url = base_url + f"/redfish/v1/Systems/System.Embedded.1/Memory"
memory_info_response = session.get(memory_info_url)
memory_info_json = memory_info_response.json()
print("\nRAM:")
for mem_socket in memory_info_json["Members"]:
	url_part = mem_socket["@odata.id"]
	memory_info_url = base_url + url_part
	memory_info_response = session.get(memory_info_url)
	memory_info_json = memory_info_response.json()
	print(memory_info_json["PartNumber"])								#TODO: SaveToFile + count

# Get storage info
storage_info_url = base_url + f"/redfish/v1/Systems/System.Embedded.1/Storage"
storage_info_response = session.get(storage_info_url)
storage_info_json = storage_info_response.json()
raid_part = storage_info_json["Members"][0]["@odata.id"]
raid_info_url = base_url + raid_part
raid_info_response = session.get(raid_info_url)
raid_info_json = raid_info_response.json()
print("\nRAID:")														#TODO: SaveToFile + multiple raid controllers
print(raid_info_json["Name"])
for drive in raid_info_json["Drives"]:
	url_part = drive["@odata.id"]
	drive_info_url = base_url + url_part
	drive_info_response = session.get(drive_info_url)
	drive_info_json = drive_info_response.json()
	print(drive_info_json["Model"])										#TODO: SaveToFile + count

# Get PSU info
power_info_url = base_url + f"/redfish/v1/Chassis/System.Embedded.1/Power#"
power_info_response = session.get(power_info_url)
power_info_json = power_info_response.json()
print("\nPSU:")
for psu in power_info_json["PowerSupplies"]:
	print(psu["PartNumber"])											#TODO: SaveToFile + count

# Get PCI info
chassis_info_url = base_url + f"/redfish/v1/Chassis/System.Embedded.1"
chassis_info_response = session.get(chassis_info_url)
chassis_info_json = chassis_info_response.json()
print("\nPCI:")
for device in chassis_info_json["Links"]["PCIeDevices"]:
	url_part = device["@odata.id"]
	device_info_url = base_url + url_part
	device_info_response = session.get(device_info_url)
	device_info_json = device_info_response.json()
	print(device_info_json["Name"],device_info_json["PartNumber"])		#TODO: SaveToFile + отсеивание встроенных устройств


#TODO: 	Каждый сервер сохраняется в свой файл. При разрыве соединения, 
#		сверять существующие файлы со списком и продолжать со следующего.
# 		Все собранные файлы запаковываются в архив и удаляются.
#		
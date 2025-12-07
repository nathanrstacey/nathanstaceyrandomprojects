all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/lab-key

firewalls_primary:
  hosts:
    fw_primary:
      ansible_host: ${fw_primary_private_ip}

firewalls_backup:
  hosts:
    fw_backup:
      ansible_host: ${fw_backup_private_ip}

ftp_servers:
  hosts:
    server1:
      ansible_host: ${server1_private_ip}

client_servers:
  hosts:
    server2:
      ansible_host: ${server2_private_ip}

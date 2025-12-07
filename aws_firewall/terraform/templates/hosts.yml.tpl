all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/nathanstacey/Desktop/quick/nathanstaceyohio6Dec2025.pem

  children:
    ftp:
      hosts:
        server1:
          ansible_host: ${server1_private_ip}

    downloader:
      hosts:
        server2:
          ansible_host: ${server2_private_ip}

    firewall_primary:
      hosts:
        fw_primary:
          ansible_host: ${fw_primary_private_ip}

    firewall_backup:
      hosts:
        fw_backup:
          ansible_host: ${fw_backup_private_ip}


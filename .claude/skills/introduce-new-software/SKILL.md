While introducing a new software, you should take care of make use of the existing Ansible playbook, and not get carried away into writing shell scripts of your own. We're taken extra care in making sure everyhing is available in the Ansible playbook, so you should be always following the protocol there.

Also, while introducing a new tool, please adhere to the common patterns. We want good consistency in our codebase.

To add a new software, you often have to first create the secret in Bitwarden, and then get the secret created in Kubernetes cluster as a Secret and so on. Occasionally you might have to infer secrets - for example if a software would be connecting to MySQL, we'd need the MySQL password to be available in the Secret.
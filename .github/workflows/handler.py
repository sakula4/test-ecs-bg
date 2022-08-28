import requests
import json

#API details
url = "https://api.github.com/repos/sakula4/test-ecs-bg/actions/workflows/33360181/dispatches"
access_token = "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"
body = json.dumps({"ref":"main"})
headers = {'Content-Type': 'application/vnd.github+json', 'Authorization': 'Bearer {}'.format(access_token)}

#Making http post request
response = requests.post(url, headers=headers, data=body, verify=False)

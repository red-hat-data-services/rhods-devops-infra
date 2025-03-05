import json
import sys
import datetime

results_file = sys.argv[1]
with open(results_file) as f:
  results = json.loads(f.read())

alerts = {}

for component in results["components"]:
    component_name = component["name"]
    container = component["containerImage"]
    git_ref = component["source"]["git"]["url"] + '/tree/' + component["source"]["git"]["revision"]
    if "violations" in component:
        for violation in component["violations"]:
            code = violation["metadata"]["code"]
            msg = violation["msg"]
            if code not in alerts:
                alerts[code] = {component_name: [msg]}
            elif component_name not in alerts[code]:
                alerts[code][component_name] = [msg]
            else:
                alerts[code][component_name].append(msg)

    if "warnings" in component:
        for warning in component["warnings"]:
            code = warning["metadata"]["code"]
            msg = warning["msg"]
            if "effective_on" not in warning["metadata"]:
                continue
            now = datetime.datetime.now(datetime.UTC)
            interval = datetime.timedelta(days=14)
            end = (now + interval).strftime("%Y-%m-%dT%H:%M:%SZ")
            effective_on = warning["metadata"]["effective_on"]
            if effective_on > end:
                continue
            msg = f"[effective on {effective_on}] {msg}"
            if code not in alerts:
                alerts[code] = { component_name: [msg]}
            elif component_name not in alerts[code]:
                alerts[code][component_name] = [msg]
            else:
                alerts[code][component_name].append(msg)

print(json.dumps(alerts,indent=2))

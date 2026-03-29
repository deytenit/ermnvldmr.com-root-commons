import json
import base64
import sys
import os
from urllib.parse import urlencode, quote

# --- ISO 3166-1 alpha-2 mapping ---
COUNTRY_MAP = {
    "LV": {"emoji": "🇱🇻", "name": "Latvia"},
    "RU": {"emoji": "🇷🇺", "name": "Russia"},
}

def deep_merge(dict1, dict2):
    """Recursively merges dict2 into dict1."""
    for key, value in dict2.items():
        if key in dict1 and isinstance(dict1[key], dict) and isinstance(value, dict):
            deep_merge(dict1[key], value)
        else:
            dict1[key] = value
    return dict1

def generate_routing_payload(routing_obj):
    """Encodes the routing object into base64 for the happ:// link."""
    json_str = json.dumps(routing_obj, separators=(',', ':'))
    b64_str = base64.b64encode(json_str.encode()).decode()
    return f"happ://routing/onadd/{b64_str}"

def generate_vless_uri(xray_config, user_name, country_code, node_chain):
    """Constructs a VLESS URI from the xray config object."""
    country = COUNTRY_MAP.get(country_code, {"emoji": "🌐", "name": country_code})
    transport = xray_config.get("streamSettings", {}).get("network", "tcp")
    uri_type = "tcp" if transport == "raw" else transport

    nodes = " > ".join(node_chain)
    remark = f"{country['emoji']} {country['name']} [{transport}] | {nodes} | {user_name}"

    settings = xray_config.get("settings", {})
    address = settings.get("address", "0.0.0.0")
    port = settings.get("port", 443)
    user_id = settings.get("id", "REDACTED")

    params = {
        "security": xray_config.get("streamSettings", {}).get("security", "tls"),
        "encryption": settings.get("encryption", "none"),
        "flow": settings.get("flow", "xtls-rprx-vision"),
        "type": uri_type,
    }

    stream_settings = xray_config.get("streamSettings", {})
    tls_settings = stream_settings.get("tlsSettings", {})
    reality_settings = stream_settings.get("realitySettings", {})

    if tls_settings:
        if "serverName" in tls_settings:
            params["sni"] = tls_settings["serverName"]
        if "fingerprint" in tls_settings:
            params["fp"] = tls_settings["fingerprint"]
        if "alpn" in tls_settings:
            params["alpn"] = ",".join(tls_settings["alpn"])

    if reality_settings:
        sni = reality_settings.get("serverName")
        if not sni and reality_settings.get("serverNames"):
            sni = reality_settings["serverNames"][0]
        if sni:
            params["sni"] = sni
        if "fingerprint" in reality_settings:
            params["fp"] = reality_settings["fingerprint"]
        if "publicKey" in reality_settings:
            params["pbk"] = reality_settings["publicKey"]
        if "shortId" in reality_settings:
            params["sid"] = reality_settings["shortId"]

    if transport == "xhttp":
        xhttp_settings = stream_settings.get("xhttpSettings", {})
        if "mode" in xhttp_settings:
            params["mode"] = xhttp_settings["mode"]
        if "path" in xhttp_settings:
            params["path"] = xhttp_settings["path"]
        if "host" in xhttp_settings:
            params["host"] = xhttp_settings["host"]
    elif transport in ["tcp", "raw"]:
        tcp_settings = stream_settings.get("tcpSettings", {})
        params["headerType"] = tcp_settings.get("header", {}).get("type", "none")

    # --- Mux settings ---
    mux_config = xray_config.get("mux", {})
    if mux_config.get("enabled", False):
        params["mux"] = "1"
        if "concurrency" in mux_config:
            params["muxConcurrency"] = str(mux_config["concurrency"])
        if "protocol" in mux_config:          # e.g. "h2mux", "smux", "xmux"
            params["muxProtocol"] = mux_config["protocol"]
        if "xudpConcurrency" in mux_config:
            params["xudpConcurrency"] = str(mux_config["xudpConcurrency"])
        if "xudpProxyUDP443" in mux_config:
            params["xudpProxyUDP443"] = mux_config["xudpProxyUDP443"]
    # (absent or enabled:false → no mux params added)

    query_str = urlencode(params)
    return f"vless://{user_id}@{address}:{port}?{query_str}#{quote(remark)}"

def main():
    if len(sys.argv) < 3:
        print("Usage: generator.py <input_json> <output_dir>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_dir = sys.argv[2]

    with open(input_path, 'r') as f:
        data = json.load(f)

    routing_payload = generate_routing_payload(data.get("routing", {}))
    templates = data.get("templates", {})
    users = data.get("users", [])

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    for user in users:
        name = user.get("name")
        psub_filename = user.get("psub", f"{name}.psub")
        psub_path = os.path.join(output_dir, psub_filename)

        lines = [routing_payload]

        for config_entry in user.get("configs", []):
            template_name = config_entry.get("template")
            
            # Start with a copy of the template if it exists
            if template_name and template_name in templates:
                # Deep copy the template
                full_config = json.loads(json.dumps(templates[template_name]))
                # Merge user's specific overrides (which might include 'country', 'nodes', or 'xray')
                deep_merge(full_config, config_entry)
            else:
                full_config = config_entry

            # Metadata is now at the top level of full_config
            country_code = full_config.get("country", "??")
            node_chain = full_config.get("nodes", ["unknown"])
            xray_config = full_config.get("xray", {})

            uri = generate_vless_uri(
                xray_config,
                name,
                country_code,
                node_chain
            )
            lines.append(uri)

        with open(psub_path, 'w') as f:
            f.write("\n".join(lines) + "\n")
        
        print(f"Generated: {psub_path}")

if __name__ == "__main__":
    main()

mkdir cis_compliance_checker
wget https://raw.githubusercontent.com/oracle-quickstart/oci-cis-landingzone-quickstart/main/scripts/cis_reports.py
python3 cis_reports.py --obp --raw -dt

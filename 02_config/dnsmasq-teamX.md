# TeamX Private DNS — Start / Stop

DNS server: 10.7.10.22
Domain: teamX.test

Records:
app.teamX.test -> 10.7.22.227
api.teamX.test -> 10.7.22.227

Start:
brew services start dnsmasq

Stop:
brew services stop dnsmasq

Restart:
brew services restart dnsmasq

Verify:
dig app.teamX.test
dig api.teamX.test


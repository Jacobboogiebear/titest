docker build -t ti_84_builder:latest .
$e=$(docker run -dt ti_84_builder:latest)
docker container cp "$e`:/export/DEMO.8xp" .
docker container rm $e
docker image rm ti_84_builder:latest
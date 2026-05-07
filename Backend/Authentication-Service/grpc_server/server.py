# grpc_server/server.py
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'generated'))

import grpc
from concurrent import futures
import auth_pb2_grpc
from .servicer import AuthServicer

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    auth_pb2_grpc.add_AuthServiceServicer_to_server(AuthServicer(), server)
    server.add_insecure_port("[::]:50051")
    server.start()
    print("gRPC server running on port 50051")
    server.wait_for_termination()
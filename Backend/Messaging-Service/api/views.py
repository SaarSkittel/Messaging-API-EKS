from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.exceptions import TokenError
from celery.result import AsyncResult
from .tasks import delete_message_task, get_all_messages_task, get_all_unread_messages_task, read_message_task, write_message_task, create_task


@api_view(["GET"])
def get_all_messages(request):
    try:
        user_id = request.user_id  # set by middleware
        friend_id = request.GET.get("id")
        task = get_all_messages_task.apply_async(args=(user_id, friend_id))
        return Response(task.get())
    except Exception as e:
        print(f"Error: {e}")
        return Response(status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
def get_all_unread_messages(request):
    try:
        user_id = request.user_id
        friend_id = request.GET.get("id")
        task = get_all_unread_messages_task.apply_async(args=(user_id, friend_id))
        return Response(task.get())
    except Exception as e:
        print(f"Error: {e}")
        return Response(status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["DELETE"])
def delete_message(request):
    try:
        user_id = request.user_id
        friend_id = request.data["user_conversation"]
        message_position = request.data["sort"]
        delete_message_task.apply_async(args=(user_id, friend_id, message_position))
        return Response(status=status.HTTP_200_OK)
    except Exception as e:
        print(f"Error: {e}")
        return Response(status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
def read_message(request):
    try:
        user_id = request.user_id
        friend_id = request.GET.get("id")
        task = read_message_task.apply_async(args=(user_id, friend_id))
        return Response(task.get())
    except Exception as e:
        print(f"Error: {e}")
        return Response(status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["POST"])
def write_message(request):
    try:
        user_id = request.user_id
        receiver_id = request.data["receiver"]
        data = {
            "subject": request.data["subject"],
            "message": request.data["message"],
        }
        write_message_task.apply_async(args=(user_id, receiver_id, data))
        return Response(status=status.HTTP_200_OK)
    except Exception as e:
        print(f"Error: {e}")
        return Response(status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["POST"])
def token(request):
    try:
        refresh_token = request.COOKIES.get("REFRESH_TOKEN")
        if not refresh_token:
            return Response(status=status.HTTP_400_BAD_REQUEST)
        from .jwt import verify_refresh_token, refresh_access_token
        verify_refresh_token(refresh_token)
        access_token = refresh_access_token(refresh_token)
        return Response(status=status.HTTP_200_OK, data={"access_token": str(access_token)})
    except TokenError:
        return Response(status=status.HTTP_403_FORBIDDEN)
    except Exception as e:
        print(f"Error: {e}")
        return Response(status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
def run_task(request):
    task = create_task.delay(1)
    return Response(data={"task_id": task.id}, status=status.HTTP_202_ACCEPTED)


@api_view(["GET"])
def get_status(request, task_id):
    task_result = AsyncResult(task_id)
    result = {
        "task_id": task_id,
        "task_status": task_result.status,
        "task_result": task_result.result
    }
    return Response(data=result, status=status.HTTP_200_OK)
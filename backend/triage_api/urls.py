from django.urls import path
from .views import TriageRAGResponderView

urlpatterns = [
    path('triage/rag/', TriageRAGResponderView.as_view(), name='triage-rag-responder'),
]

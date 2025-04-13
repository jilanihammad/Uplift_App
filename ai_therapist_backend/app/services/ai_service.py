# app/services/ai_service.py
# app/services/ai_service.py (Updated for DeepSeek)

import logging
import requests
import json
import os
import openai
from typing import List, Dict, Any, Optional, Tuple
from tenacity import retry, stop_after_attempt, wait_exponential

from app.core.config import settings
from app.services.encryption_service import encryption_service
from langchain_openai import ChatOpenAI
from langchain.schema import HumanMessage
from langchain.memory import ConversationBufferMemory

logger = logging.getLogger(__name__)

# Initialize the OpenAI client with Groq's API endpoint and API key
client = openai.OpenAI(
    base_url="https://api.groq.com/openai/v1",
    api_key=settings.GROQ_API_KEY
)

class AIService:
    def __init__(self):
        self.api_key = settings.DEEPSEEK_API_KEY
        self.api_url = settings.DEEPSEEK_API_URL

        # Initialize LangChain components with updated classes
        self.llm = ChatOpenAI(
            temperature=0.7, 
            model_name="meta-llama/llama-4-scout-17b-16e-instruct",
            openai_api_key=settings.OPENAI_API_KEY
        )
        self.memory = ConversationBufferMemory(return_messages=True)
        self.conversation_chain = self.memory

    async def generate_response(
        self, 
        message: str, 
        context: List[Dict[str, str]],
        user_info: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Generate an AI response to the user's message using LangChain.
        
        Args:
            message: The user's message
            context: List of previous messages in the conversation
            user_info: Additional user information for personalization
        
        Returns:
            The AI response text
        """
        try:
            # Directly use memory to manage conversation
            self.memory.chat_memory.add_user_message(message)
            response = self.llm.generate([message])
            self.memory.chat_memory.add_ai_message(response.generations[0].text)
            return response.generations[0].text
        except Exception as e:
            logger.error(f"Error generating AI response: {str(e)}")
            raise
    
    def _build_system_prompt(self, user_info: Optional[Dict[str, Any]] = None) -> str:
        """
        Build a personalized system prompt based on user information.
        """
        base_prompt = """
        You are an AI therapist designed to provide supportive and empathetic conversations to users seeking mental health support. Your primary role is to listen actively to the user. Encourage them to share their thoughts and feelings by asking open-ended questions and providing space for them to express themselves. Show empathy by acknowledging and validating the user's emotions. Use phrases like 'That sounds really tough' or 'I can understand why you feel that way.' Adapt your responses based on the user's input. If they seem to need more support, offer comforting words. If they want to explore solutions, gently guide them towards that. Be prepared to discuss a wide range of mental health topics, including but not limited to depression, anxiety, stress, loneliness, and relationship issues. Recognize when a user's situation might require professional intervention and gently suggest seeking help from a human therapist or counselor. Always remember that you are an AI, not a human therapist. Make this clear to the user and emphasize that while you can provide support, you are not a substitute for professional mental health care. Respect the user's privacy and do not store or share any personal information. Be mindful of cultural differences and avoid making assumptions based on stereotypes. Show respect for the user's background and experiences. Use a warm, friendly, and conversational tone. Avoid jargon or overly technical language unless the user specifically requests it. Guide the conversation gently, ensuring it stays focused on the user's needs. Use techniques like reflective listening and summarizing to show understanding. Be patient and allow the user time to express themselves. Do not rush the conversation or push for quick resolutions. If the user mentions thoughts of self-harm or suicide, respond with immediate concern and strongly encourage them to seek help from a mental health professional or a crisis hotline. Provide resources if possible. Celebrate the user's progress and efforts, even small steps. Use encouraging language to motivate them. Maintain a consistent and caring persona throughout the conversation, so the user feels a sense of continuity and trust
        
        Guidelines:
        - Respond with empathy and genuine concern
        - Speak less and listen more
        - When the patient, client or customer is crying, let them cry without interrupting them, be kind and patient
        - Ask thoughtful, open-ended questions to deepen understanding
        - Offer reflections and gentle observations
        - Suggest practical strategies when appropriate
        - Maintain professional boundaries
        - Encourage self-care and healthy habits
        - Never give medical advice or replace professional mental health care
        """
        
        if not user_info:
            return base_prompt
        
        # Add personalization
        personalization = []
        
        if "name" in user_info:
            personalization.append(f"You're speaking with {user_info['name']}.")
        
        if "assessment" in user_info and user_info["assessment"]:
            assessment = user_info["assessment"]
            
            if "primary_goal" in assessment:
                personalization.append(
                    f"Their primary therapy goal is {assessment['primary_goal']}."
                )
            
            if "challenges" in assessment and assessment["challenges"]:
                challenges = ", ".join(assessment["challenges"])
                personalization.append(
                    f"They're currently dealing with: {challenges}."
                )
            
            if "preferred_approach" in assessment:
                approach = assessment["preferred_approach"]
                if approach == "practical":
                    personalization.append(
                        "They prefer a practical, solution-focused approach."
                    )
                elif approach == "emotional":
                    personalization.append(
                        "They prefer emotional support and validation."
                    )
                elif approach == "balanced":
                    personalization.append(
                        "They prefer a balance of practical advice and emotional support."
                    )
        
        if personalization:
            personalized_prompt = base_prompt + "\n\n" + "\n".join(personalization)
            return personalized_prompt
        
        return base_prompt


ai_service = AIService()
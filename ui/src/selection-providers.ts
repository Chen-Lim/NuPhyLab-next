// Official model catalogs checked 2026-11-06; see docs/SELECTION_R2.md.
// Presets never imply account access or automatically opt a user into image upload.
export const providers=[
 {id:'openAI',name:'OpenAI',region:'海外',endpoint:'https://api.openai.com/v1/responses',protocol:'responses',models:['gpt-6-astra','gpt-6.1-sol','gpt-6.1-terra','gpt-6-luna'],url:'https://developers.openai.com/api/docs/models'},
 {id:'anthropic',name:'Claude',region:'海外',endpoint:'https://api.anthropic.com/v1/messages',protocol:'anthropicMessages',models:['claude-haiku-5-5','claude-sonnet-5-5','claude-opus-5-5','claude-fable-5-1'],url:'https://platform.claude.com/docs/en/models/overview'},
 {id:'gemini',name:'Gemini',region:'海外',endpoint:'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',protocol:'chatCompletions',models:['gemini-3.8-flash','gemini-3.6-flash','gemini-3.5-flash-lite','gemini-3.1-flash-lite','gemini-3.1-pro-preview'],url:'https://aistudio.google.com/docs/models'},
 {id:'deepSeek',name:'DeepSeek',region:'国内',endpoint:'https://api.deepseek.com/chat/completions',protocol:'chatCompletions',models:['deepseek-flash','deepseek-v4-pro'],url:'https://api-docs.deepseek.com/'},
 {id:'qwenChina',name:'通义千问',region:'北京',endpoint:'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',protocol:'chatCompletions',models:['qwen-plus','qwen3.8-max','qwen3.7-plus','qwen3.8-flash','qwen3.7-max','qwen3.7-flash'],url:'https://docs.modelstudio.console.alibabacloud.com/en/model-studio/models'},
 {id:'qwenInternational',name:'通义千问',region:'新加坡',endpoint:'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions',protocol:'chatCompletions',models:['qwen-plus','qwen3.8-max','qwen3.7-plus','qwen3.8-flash','qwen3.7-max','qwen3.7-flash'],url:'https://docs.modelstudio.console.alibabacloud.com/en/model-studio/models'},
 {id:'openRouter',name:'OpenRouter',region:'聚合',endpoint:'https://openrouter.ai/api/v1/chat/completions',protocol:'chatCompletions',models:['openrouter/auto','openai/gpt-6-astra','openai/gpt-6.1-sol','openai/gpt-6.1-terra','openai/gpt-6-luna','anthropic/claude-sonnet-5.5','anthropic/claude-opus-5.5','google/gemini-3.8-flash','deepseek/deepseek-v4.1-flash-1017'],url:'https://openrouter.ai/models'},
 {id:'custom',name:'自定义服务',region:'兼容接口',endpoint:'',protocol:'chatCompletions',models:[],url:''},
];

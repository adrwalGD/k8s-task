using System;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using cartservice.cartstore;
using cartservice.services;
using Microsoft.Extensions.Caching.StackExchangeRedis;
using StackExchange.Redis; // Required for ConfigurationOptions

namespace cartservice
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        // This method gets called by the runtime. Use this method to add services to the container.
        // For more information on how to configure your application, visit https://go.microsoft.com/fwlink/?LinkID=398940
        public void ConfigureServices(IServiceCollection services)
        {
            // --- Read Redis configuration from IConfiguration ---
            // IConfiguration reads from various sources, including environment variables by default
            string redisAddress = Configuration["REDIS_ADDR"];
            string redisPassword = Configuration["REDIS_PASSWORD"]; // <-- Read the password

            string spannerProjectId = Configuration["SPANNER_PROJECT"];
            string spannerConnectionString = Configuration["SPANNER_CONNECTION_STRING"];
            string alloyDBConnectionString = Configuration["ALLOYDB_PRIMARY_IP"];

            if (!string.IsNullOrEmpty(redisAddress))
            {
                Console.WriteLine($"Attempting to use Redis cache at: {redisAddress}"); // Good to log
                services.AddStackExchangeRedisCache(options =>
                {
                    // --- Configure using ConfigurationOptions ---
                    var configurationOptions = new StackExchange.Redis.ConfigurationOptions()
                    {
                        // Assuming redisAddress is in "hostname:port" format
                        EndPoints = { redisAddress },
                        // Prevent connect failures from killing the process early
                        AbortOnConnectFail = false
                    };

                    // --- Explicitly set the password if provided ---
                    if (!string.IsNullOrEmpty(redisPassword))
                    {
                        Console.WriteLine("REDIS_PASSWORD environment variable found, using password.");
                        configurationOptions.Password = redisPassword;
                    }
                    else
                    {
                        Console.WriteLine("REDIS_PASSWORD environment variable not found or empty, connecting without password.");
                    }

                    // --- Assign the configured options object ---
                    options.ConfigurationOptions = configurationOptions;

                    // --- Remove the old line that only set the address ---
                    // options.Configuration = redisAddress;
                });

                // Register RedisCartStore only if Redis is configured
                services.AddSingleton<ICartStore, RedisCartStore>();
            }
            else if (!string.IsNullOrEmpty(spannerProjectId) || !string.IsNullOrEmpty(spannerConnectionString))
            {
                services.AddSingleton<ICartStore, SpannerCartStore>();
            }
            else if (!string.IsNullOrEmpty(alloyDBConnectionString))
            {
                Console.WriteLine("Creating AlloyDB cart store");
                services.AddSingleton<ICartStore, AlloyDBCartStore>();
            }
            else
            {
                Console.WriteLine("No cache/store specified. Starting a cart service using in memory store");
                // Using AddDistributedMemoryCache means RedisCartStore will use an in-memory cache
                // This might be confusing, consider a separate InMemoryCartStore class if needed.
                services.AddDistributedMemoryCache();
                services.AddSingleton<ICartStore, RedisCartStore>(); // This will now use the Memory Cache backend
            }


            services.AddGrpc();
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }

            app.UseRouting();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapGrpcService<CartService>();
                endpoints.MapGrpcService<cartservice.services.HealthCheckService>();

                endpoints.MapGet("/", async context =>
                {
                    await context.Response.WriteAsync("Communication with gRPC endpoints must be made through a gRPC client. To learn how to create a client, visit: https://go.microsoft.com/fwlink/?linkid=2086909");
                });
            });
        }
    }
}

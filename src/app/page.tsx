import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { Chat } from "@/components/chat";

export const dynamic = "force-dynamic";

export default async function Home() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-4">
      <div className="w-full max-w-2xl">
        <h1 className="mb-6 text-2xl font-bold">
          Hey, {user.user_metadata?.display_name || user.email}
        </h1>
        <Chat />
      </div>
    </main>
  );
}
